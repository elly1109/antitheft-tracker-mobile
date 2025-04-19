import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'dart:convert';

class AIProtectionService {
  final _storage = const FlutterSecureStorage();
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  List<List<double>> _behaviorData = [];
  bool _isLocked = false;
  final String _apiUrl = 'http://10.0.2.2:5000/detect_anomaly';
  String? _deviceId;

  Future<void> init(String deviceId) async {
    _deviceId = deviceId;
    // Initialize background service
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'antitheft_tracker_channel',
        initialNotificationTitle: 'AntiTheft Tracker',
        initialNotificationContent: 'Protecting your device',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
    service.startService();

    // Monitor accelerometer for suspicious behavior
    _accelSubscription = accelerometerEvents.listen((event) {
      _behaviorData.add([event.x, event.y, event.z, 0, 0, 0]); // Pad for model
      if (_behaviorData.length > 50) {
        _behaviorData.removeAt(0);
        _checkBehavior();
      }
    });
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    // Ensure Dart plugin registrants are available
    WidgetsFlutterBinding.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });
      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    // Periodic monitoring
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: 'AntiTheft Tracker',
            content: 'Monitoring for uninstall attempts',
          );
        }
      }
      debugPrint('Background service running');
    });
  }

  @pragma('vm:entry-point')
  static bool onIosBackground(ServiceInstance service) {
    debugPrint('iOS background fetch');
    return true;
  }

  Future<void> _checkBehavior() async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': _behaviorData, 'device_id': _deviceId}),
      );
      final result = jsonDecode(response.body);
      if (result['is_anomaly'] == true) {
        debugPrint('Suspicious behavior detected: Potential uninstall attempt');
        _isLocked = true;
      }
    } catch (e) {
      debugPrint('AI detection error: $e');
    }
  }

  Future<bool> authenticate(String password) async {
    final stored = await _storage.read(key: 'app_password');
    return stored == password;
  }

  Future<void> setPassword(String password) async {
    await _storage.write(key: 'app_password', value: password);
  }

  bool get isLocked => _isLocked;

  void unlock() => _isLocked = false;

  void dispose() {
    _accelSubscription?.cancel();
  }
}