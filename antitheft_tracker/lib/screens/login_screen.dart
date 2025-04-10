import 'package:flutter/material.dart';
import '../components/button.dart';
import '../components/input.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _deviceIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  void _login() async {
    setState(() => _isLoading = true);
    try {
      final response = await apiService.login(_deviceIdController.text, _passwordController.text);
      final token = response['token'];
      await authService.storeToken(token);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login successful')));
      Navigator.pushNamed(context, '/tracker', arguments: _deviceIdController.text);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomInput(hintText: 'Device ID', controller: _deviceIdController),
            SizedBox(height: 10),
            CustomInput(hintText: 'Password', obscureText: true, controller: _passwordController),
            SizedBox(height: 20),
            CustomButton(
              text: _isLoading ? 'Logging in...' : 'Login',
              onPressed: _isLoading ? () {} : _login, // Non-null callback
              color: _isLoading ? Colors.grey : Colors.blue,
            ),
            SizedBox(height: 10),
            CustomButton(
              text: 'Go to Register',
              color: Colors.grey,
              onPressed: () => Navigator.pushNamed(context, '/register'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}