import 'package:flutter/material.dart';
import '../components/button.dart';
import '../components/input.dart';
import '../services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _deviceIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  void _register() async {
    setState(() => _isLoading = true);
    try {
      await apiService.register(_deviceIdController.text, _passwordController.text);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registration successful')));
      Navigator.pushNamed(context, '/login');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Register Device')),
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
              text: _isLoading ? 'Registering...' : 'Register',
              onPressed: _isLoading ? () {} : _register, // Always provide a non-null callback
              color: _isLoading ? Colors.grey : Colors.blue, // Grey out when loading
            ),
            SizedBox(height: 10),
            CustomButton(
              text: 'Go to Login',
              color: Colors.grey,
              onPressed: () => Navigator.pushNamed(context, '/login'),
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