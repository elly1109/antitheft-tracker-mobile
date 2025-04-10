import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'navigation/app_router.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(AntiTheftTrackerApp());
}

class AntiTheftTrackerApp extends StatelessWidget {
  final _router = AppRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AntiTheft Tracker',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/register',
      onGenerateRoute: _router.generateRoute,
    );
  }
}