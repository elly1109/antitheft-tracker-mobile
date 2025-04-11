import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../components/button.dart';
import '../components/location_card.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/crypto.dart';
import '../utils/constants.dart';

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
  int _failedUnlockAttempts = 0;
  bool _simChanged = false;
  bool _forcedPowerOff = false;
  bool _isStolen = false;

  @override
  void initState() {
    super.initState();
    _startTracking();
    _setupTheftDetection();
    _checkStolenStatus();
  }

  Future<void> _startTracking() async {
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
    _timer = Timer.periodic(Duration(seconds: 5), (_) => _sendLocation());
  }

  void _setupTheftDetection() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      final delta = (magnitude - _lastAccelMagnitude).abs();

      if (delta > 10.0 && !_theftDetected) {
        debugPrint('Theft detected: Sudden movement (delta: $delta)');
        _activateTheftMode('Sudden movement detected');
      }
      _lastAccelMagnitude = magnitude;
    });

    _monitorSuspiciousBehavior();
  }

  void _monitorSuspiciousBehavior() {
    Timer.periodic(Duration(seconds: 10), (_) {
      if (!_theftDetected) {
        _failedUnlockAttempts += Random().nextInt(2);
        _simChanged = Random().nextBool() && Random().nextInt(100) < 10;
        _forcedPowerOff = Random().nextBool() && Random().nextInt(100) < 5;

        if (_failedUnlockAttempts > 3) {
          _activateTheftMode('Multiple failed unlock attempts');
        } else if (_simChanged) {
          _activateTheftMode('SIM card changed');
        } else if (_forcedPowerOff) {
          _activateTheftMode('Forced power-off detected');
        }
      }
    });
  }

  void _activateTheftMode(String reason) {
    setState(() {
      _theftDetected = true;
      _status = 'Theft mode activated: $reason';
    });
    _sendLocation(immediate: true);
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 2), (_) => _sendLocation());
  }

  Future<void> _sendLocation({bool immediate = false}) async {
    try {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final timestamp = DateTime.now().toIso8601String();
      final data = '$_deviceId,${position.latitude},${position.longitude},$timestamp${_theftDetected ? ",theft" : ""}';

      debugPrint('Raw data before encryption: $data');
      final encryptedData = crypto.encryptData(data);

      final response = await apiService.sendUpdate(_token!, encryptedData);
      setState(() {
        _location = position;
        _status = response['status'] == 'success'
            ? 'Location sent${_theftDetected ? " (Theft mode)" : ""}'
            : 'Error: ${response['message']}';
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

  Future<void> _checkStolenStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$apiUrl/check-stolen/$_deviceId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      setState(() => _isStolen = data['status'] == 'stolen');
      if (_isStolen) {
        _status = 'Device marked as stolen';
      }
    } catch (e) {
      debugPrint('Error checking stolen status: $e');
    }
  }

  Future<void> _reportStolen() async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/report-stolen'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        setState(() {
          _isStolen = true;
          _status = 'Device reported stolen';
        });
      }
    } catch (e) {
      setState(() => _status = 'Error reporting stolen: $e');
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
    _accelerometerSubscription?.cancel();
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
                  userAgentPackageName: 'com.banal.anti-theft_tracker',
                ),
                MarkerLayer(
                  markers: _location != null
                      ? [
                    Marker(
                      point: LatLng(_location!.latitude, _location!.longitude),
                      width: 80,
                      height: 80,
                      child: Icon(Icons.location_pin, color: _theftDetected ? Colors.red : Colors.blue, size: 40),
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
                Text(_status, style: TextStyle(fontSize: 16, color: _theftDetected || _isStolen ? Colors.red : Colors.white)),
                if (_location != null)
                  LocationCard(
                    latitude: _location!.latitude,
                    longitude: _location!.longitude,
                    timestamp: _location!.timestamp.toString(),
                  ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: CustomButton(
                        text: 'Send Update',
                        onPressed: () => _sendLocation(immediate: true),
                        color: Colors.blue,
                        textColor: Colors.white
                      ),
                    ),
                    SizedBox(width: 8), // Spacing between buttons
                    Expanded(
                      child: CustomButton(
                        text: 'Report Stolen',
                        onPressed: _reportStolen,
                        color: Colors.orange,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: CustomButton(
                        text: 'Logout',
                        onPressed: _logout,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}