import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class AuthService {
  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$apiUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> register(String email, String password, String deviceId) async {
    final response = await http.post(
      Uri.parse('$apiUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'deviceId': deviceId,
      }),
    );
    return jsonDecode(response.body);
  }

  Future<void> saveToken(String token, String deviceId) async {
    await _storage.write(key: 'token', value: token);
    await _storage.write(key: 'device_id', value: deviceId);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: 'token');
  }


  Future<String?> getDeviceId() async {
    return await _storage.read(key: 'device_id');
  }

  Future<void> removeToken() async {
    await _storage.delete(key: 'token');
    await _storage.delete(key: 'device_id');

  }
}

final authService = AuthService();