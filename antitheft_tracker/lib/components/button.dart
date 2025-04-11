import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed; // Must be VoidCallback, not Future<void> Function()
  final Color? color, textColor;

  const CustomButton({required this.text, required this.onPressed, this.color, this.textColor });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? Theme.of(context).primaryColor,
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        foregroundColor: Colors.white, // Set text/icon color to white
        textStyle: TextStyle(color: this.textColor), // Ensure text is white
      ),
      child: Text(text),
    );
  }
}