import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart'; // Import sensors_plus
import '../components/button.dart';
import '../components/location_card.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/crypto.dart';

class TrackerScreen extends StatefulWidget {
  @override
  _TrackerScreenState createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  Position? _location;
  String _status = 'Starting tracker...';
  String? _token;
  String? _deviceId;
  Timer? _timer;
  final MapController _mapController = MapController();
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  double _lastAccelMagnitude = 0.0;
  bool _theftDetected = false;

  @override
  void initState() {
    super.initState();
    _startTracking();
    _setupTheftDetection();
  }

  void _startTracking() async {
    _token = await authService.getToken();
    if (_token == null) {
      setState(() => _status = 'Not logged in');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    _deviceId = ModalRoute.of(context)?.settings.arguments as String?;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _status = 'Location services disabled');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _status = 'Location permission denied');
        return;
      }
    }

    await _sendLocation();
    _timer = Timer.periodic(Duration(seconds: 10), (_) => _sendLocation());
  }

  void _setupTheftDetection() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      final magnitude = (event.x * event.x + event.y * event.y + event.z * event.z).sqrt();
      final delta = (magnitude - _lastAccelMagnitude).abs();

      // Detect sudden movement (e.g., theft) if delta exceeds threshold
      if (delta > 10.0 && !_theftDetected) { // Adjust threshold as needed
        debugPrint('Theft detected: Sudden movement (delta: $delta)');
        setState(() => _status = 'Theft detected! Sending location...');
        _theftDetected = true;
        _sendLocation(); // Immediate update
      }
      _lastAccelMagnitude = magnitude;
    });
  }

  Future<void> _sendLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final timestamp = DateTime.now().toIso8601String();
      final data = '$_deviceId,${position.latitude},${position.longitude},$timestamp';

      debugPrint('Raw data before encryption: $data');
      final encryptedData = crypto.encryptData(data);

      await apiService.sendUpdate(_token!, encryptedData);
      setState(() {
        _location = position;
        _status = 'Location sent successfully${_theftDetected ? " (Theft mode)" : ""}';
      });
      if (_location != null) {
        _mapController.move(LatLng(_location!.latitude, _location!.longitude), 13.0);
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
      if (e.toString().contains('401')) {
        _timer?.cancel();
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  void _logout() async {
    _timer?.cancel();
    _accelerometerSubscription?.cancel();
    await authService.removeToken();
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _accelerometerSubscription?.cancel(); // Clean up accelerometer stream
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Tracker')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _location != null
                    ? LatLng(_location!.latitude, _location!.longitude)
                    : LatLng(0.0, 0.0),
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.antitheft_tracker',
                ),
                MarkerLayer(
                  markers: _location != null
                      ? [
                    Marker(
                      point: LatLng(_location!.latitude, _location!.longitude),
                      width: 80,
                      height: 80,
                      child: Icon(Icons.location_pin, color: Colors.red, size: 40),
                    ),
                  ]
                      : [],
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Text(_status, style: TextStyle(fontSize: 16)),
                if (_location != null)
                  LocationCard(
                    latitude: _location!.latitude,
                    longitude: _location!.longitude,
                    timestamp: _location!.timestamp.toString(),
                  ),
                SizedBox(height: 20),
                CustomButton(text: 'Send Update Now', onPressed: _sendLocation),
                SizedBox(height: 10),
                CustomButton(
                  text: 'Logout',
                  color: Colors.red,
                  onPressed: _logout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}