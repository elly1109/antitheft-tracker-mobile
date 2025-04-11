import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../components/button.dart';
import 'dart:convert';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _status = '';
  String? _deviceId;
  bool _isDeviceIdLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getDeviceId();
    });
  }

  Future<void> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (!mounted) return;
      if (Theme.of(context).platform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceId = androidInfo.id;
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor;
      }
      debugPrint('Device ID: $_deviceId');
    } catch (e) {
      _deviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('Error getting device ID: $e');
      if (mounted) {
        setState(() => _status = 'Device ID error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isDeviceIdLoading = false);
      }
    }
  }

  Future<void> _register() async {
    if (_isDeviceIdLoading) {
      setState(() => _status = 'Device ID still loading, please wait');
      return;
    }
    if (_deviceId == null) {
      setState(() => _status = 'Device ID not ready, retrying...');
      await _getDeviceId();
      if (_deviceId == null) {
        setState(() => _status = 'Failed to get Device ID');
        return;
      }
    }

    setState(() => _status = 'Registering...');
    try {
      final response = await apiService.register(
        _emailController.text.trim(),
        _passwordController.text,
        _deviceId!,
      ).timeout(Duration(seconds: 10), onTimeout: () {
        throw Exception('Request timed out');
      });

      debugPrint('Register response: $response');
      setState(() => _status = response['message'] ?? 'Unknown response');

      if (response['status'] == 'success') {
        Navigator.pushReplacementNamed(context, '/login');
      } else {
        setState(() => _status = response['message'] ?? 'Registration failed');
      }
    } catch (e) {
      debugPrint('Registration error: $e');
      setState(() => _status = 'Registration failed: $e');
    }
  }

  void _onRegisterPressed() {
    _register(); // Wrap async call in a sync function
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Register')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            SizedBox(height: 20),
            CustomButton(
              text: 'Register',
              onPressed: _isDeviceIdLoading ? null : _onRegisterPressed, // Use sync wrapper
            ),
            SizedBox(height: 10),
            if (_isDeviceIdLoading) CircularProgressIndicator(),
            Text(
              _status,
              style: TextStyle(color: _status.contains('failed') ? Colors.red : Colors.black),
            ),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
              child: Text('Already have an account? Login'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}