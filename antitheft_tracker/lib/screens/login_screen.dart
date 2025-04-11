import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../components/button.dart'; // Assuming this exists

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _status = '';

  void _login() async {
    final response = await authService.login(
      _emailController.text,
      _passwordController.text,
    );
    setState(() => _status = response['message'] ?? 'Login failed');
    if (response['status'] == 'success') {
      final token = response['token'];
      await authService.saveToken(token);
      Navigator.pushReplacementNamed(context, '/tracker', arguments: response['device_id']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
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
            CustomButton(text: 'Login', onPressed: _login, textColor: Colors.white,),
            SizedBox(height: 10),
            Text(_status),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/register'),
              child: Text('Need an account? Register'),
            ),
          ],
        ),
      ),
    );
  }
}