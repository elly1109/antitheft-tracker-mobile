import 'package:flutter/material.dart';
import '../screens/register_screen.dart';
import '../screens/login_screen.dart';
import '../screens/tracker_screen.dart';

class AppRouter {
  Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/register':
        return MaterialPageRoute(builder: (_) => const RegisterScreen());
      case '/login':
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case '/tracker':
      // Extract deviceId from arguments
        final deviceId = settings.arguments as String?;
        if (deviceId == null) {
          // Redirect to login if no deviceId is provided
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        return MaterialPageRoute(
          builder: (_) => TrackerScreen(deviceId: deviceId),
        );
      default:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
    }
  }
}