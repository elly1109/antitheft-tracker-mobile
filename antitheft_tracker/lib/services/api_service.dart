import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class ApiService {
  Future<Map<String, dynamic>> register(String email, String password, String deviceId, {required String ethAddress}) async {
    final response = await http.post(
      Uri.parse('$apiUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password, 'device_id': deviceId, 'eth_address': ethAddress}),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> sendUpdate(String token, String data) async {
    final response = await http.post(
      Uri.parse('$apiUrl/update'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'data': data}),
    );
    return jsonDecode(response.body);
  }
}

final apiService = ApiService();