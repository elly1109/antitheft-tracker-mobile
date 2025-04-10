import 'package:flutter/material.dart';

class LocationCard extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String timestamp;

  const LocationCard({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: EdgeInsets.all(15),
        child: Column(
          children: [
            Text('Latitude: ${latitude.toStringAsFixed(4)}'),
            Text('Longitude: ${longitude.toStringAsFixed(4)}'),
            Text('Timestamp: ${DateTime.parse(timestamp).toLocal()}'),
          ],
        ),
      ),
    );
  }
}