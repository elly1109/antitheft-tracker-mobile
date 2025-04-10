import 'package:flutter/material.dart';
import '../screens/register_screen.dart';
import '../screens/login_screen.dart';
import '../screens/tracker_screen.dart';

class AppRouter {
  Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/register':
        return MaterialPageRoute(builder: (_) => RegisterScreen());
      case '/login':
        return MaterialPageRoute(builder: (_) => LoginScreen());
      case '/tracker':
        return MaterialPageRoute(
          builder: (_) => TrackerScreen(),
          settings: settings, // Pass deviceId as argument
        );
      default:
        return MaterialPageRoute(builder: (_) => RegisterScreen());
    }
  }
}