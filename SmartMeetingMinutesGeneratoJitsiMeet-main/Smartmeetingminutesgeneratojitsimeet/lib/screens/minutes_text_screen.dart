import 'package:flutter/material.dart';

/// Displays meeting minutes as plain text (from app.py meeting_minutes.txt)
class MinutesTextScreen extends StatelessWidget {
  final String minutesText;

  const MinutesTextScreen({super.key, required this.minutesText});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meeting Minutes')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          minutesText,
          style: const TextStyle(height: 1.5, fontSize: 15),
        ),
      ),
    );
  }
}
