import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../components/button.dart';
import '../components/location_card.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/crypto.dart';
import '../utils/constants.dart';

class TrackerScreen extends StatefulWidget {
  final String deviceId;

  const TrackerScreen({super.key, required this.deviceId});

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
  List<String> _nearbyDevices = [];
  StreamSubscription<List<ScanResult>>? _bleScanSubscription;
  List<Map<String, dynamic>> _wifiNetworks = [];
  bool _isConnectedToKnownNetwork = false;
  final List<String> _knownSSIDs = ['MyTrustedNetwork', 'HomeWiFi'];
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _startTracking();
    _setupTheftDetection();
    _checkStolenStatus();
    _setupBluetoothDetection();
    _setupWiFiDetection();
  }

  Future<void> _setupBluetoothDetection() async {
    try {
      final permissions = [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ];
      bool allGranted = true;

      for (var permission in permissions) {
        if (await permission.isDenied) {
          final status = await permission.request();
          if (status.isDenied || status.isPermanentlyDenied) {
            allGranted = false;
            break;
          }
        }
      }

      if (!allGranted) {
        setState(() => _status = 'Bluetooth or location permissions denied. Please enable in settings.');
        await openAppSettings();
        return;
      }

      if (await FlutterBluePlus.isOn == false) {
        setState(() => _status = 'Please enable Bluetooth');
        await FlutterBluePlus.turnOn();
        return;
      }

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      _bleScanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          final deviceId = result.device.id.toString();
          final rssi = result.rssi;
          if (!_nearbyDevices.contains(deviceId)) {
            setState(() {
              _nearbyDevices.add(deviceId);
              _status = 'Detected Bluetooth device: $deviceId (RSSI: $rssi)';
            });
            debugPrint('Bluetooth device detected: $deviceId, RSSI: $rssi');
            if (_nearbyDevices.length > 1 && !_theftDetected) {
              _activateTheftMode('Unknown Bluetooth device detected');
            }
          }
        }
      }, onError: (e) {
        setState(() => _status = 'Bluetooth scan error: $e');
      });

      await Future.delayed(const Duration(seconds: 10));
      await FlutterBluePlus.stopScan();
    } catch (e) {
      setState(() => _status = 'Bluetooth setup error: $e');
      if (e.toString().contains('MissingPluginException')) {
        debugPrint('Permission handler plugin not initialized. Rebuild the app.');
      }
    }
  }

  Future<void> _setupWiFiDetection() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _status = 'WiFi detection only supported on Android');
      return;
    }

    try {
      final permissions = [
        Permission.locationWhenInUse,
        Permission.nearbyWifiDevices,
      ];
      bool allGranted = true;

      for (var permission in permissions) {
        if (await permission.isDenied) {
          final status = await permission.request();
          if (status.isDenied || status.isPermanentlyDenied) {
            allGranted = false;
            break;
          }
        }
      }

      if (!allGranted) {
        setState(() => _status = 'WiFi permissions denied. Please enable in settings.');
        await openAppSettings();
        return;
      }

      final wifiList = await WiFiForIoTPlugin.loadWifiList();
      _wifiNetworks = wifiList.cast<Map<String, dynamic>>();
      setState(() {
        _status = 'Detected ${_wifiNetworks.length} WiFi networks';
      });

      for (var network in _wifiNetworks) {
        final ssid = network['ssid'] as String?;
        if (ssid != null && _knownSSIDs.contains(ssid)) {
          final password = await _storage.read(key: 'wifi_$ssid') ?? 'your_network_password';
          bool connected = await WiFiForIoTPlugin.connect(
            ssid,
            password: password,
            security: NetworkSecurity.WPA,
          );
          if (connected) {
            setState(() {
              _isConnectedToKnownNetwork = true;
              _status = 'Connected to $ssid';
            });
            break;
          }
        }
      }

      if (_wifiNetworks.any((n) => n['ssid'] != null && !_knownSSIDs.contains(n['ssid']) && (n['level'] as int) > -50)) {
        _activateTheftMode('Unknown strong WiFi network detected');
      }
    } catch (e) {
      setState(() => _status = 'WiFi scan error: $e');
      if (e.toString().contains('MissingPluginException')) {
        debugPrint('WiFi plugin not initialized. Rebuild the app.');
      }
    }
  }

  Future<void> _startTracking() async {
    _token = await authService.getToken();
    _deviceId = await authService.getDeviceId() ?? widget.deviceId;
    if (_token == null || _deviceId == null) {
      setState(() => _status = 'Not logged in or missing device ID');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _status = 'Location services disabled');
      await Geolocator.openLocationSettings();
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
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _sendLocation());
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
    Timer.periodic(const Duration(seconds: 10), (_) {
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
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _sendLocation());
  }

  Future<void> _sendLocation({bool immediate = false}) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.wifi && _isConnectedToKnownNetwork) {
        debugPrint('Sending location over WiFi');
      } else if (connectivityResult == ConnectivityResult.none) {
        setState(() => _status = 'No network connection');
        return;
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final timestamp = DateTime.now().toIso8601String();
      final payload = {
        'device_id': _deviceId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': timestamp,
        'is_theft': _theftDetected,
      };

      debugPrint('Raw payload: $payload');
      final encryptedData = crypto.encryptData(payload);
      debugPrint('Encrypted payload: $encryptedData');

      final response = await apiService.sendUpdate(_token!, encryptedData);
      debugPrint('Update response: $response');

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
      setState(() => _status = 'Error sending location: $e');
      debugPrint('Location send error: $e');
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
    _bleScanSubscription?.cancel();
    await FlutterBluePlus.stopScan();
    await authService.removeToken();
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _accelerometerSubscription?.cancel();
    _bleScanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tracker')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _location != null
                    ? LatLng(_location!.latitude, _location!.longitude)
                    : const LatLng(0.0, 0.0),
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.banal.anti_theft_tracker',
                ),
                MarkerLayer(
                  markers: _location != null
                      ? [
                    Marker(
                      point: LatLng(_location!.latitude, _location!.longitude),
                      width: 80,
                      height: 80,
                      child: Icon(
                        Icons.location_pin,
                        color: _theftDetected ? Colors.red : Colors.blue,
                        size: 40,
                      ),
                    ),
                  ]
                      : [],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 16,
                    color: _theftDetected || _isStolen ? Colors.red : Colors.black,
                  ),
                ),
                if (_nearbyDevices.isNotEmpty)
                  Text(
                    'Nearby Bluetooth Devices: ${_nearbyDevices.length}',
                    style: const TextStyle(fontSize: 14),
                  ),
                if (_wifiNetworks.isNotEmpty)
                  Text(
                    'Nearby WiFi Networks: ${_wifiNetworks.length}',
                    style: const TextStyle(fontSize: 14),
                  ),
                if (_location != null)
                  LocationCard(
                    latitude: _location!.latitude,
                    longitude: _location!.longitude,
                    timestamp: _location!.timestamp.toString(),
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: CustomButton(
                        text: 'Send Update',
                        onPressed: () => _sendLocation(immediate: true),
                        color: Colors.blue,
                        textColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CustomButton(
                        text: 'Report Stolen',
                        onPressed: _reportStolen,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
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