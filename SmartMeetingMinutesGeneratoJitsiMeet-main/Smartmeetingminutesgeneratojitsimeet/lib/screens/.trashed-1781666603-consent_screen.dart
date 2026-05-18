// User consent screen before recording.
import 'package:flutter/material.dart';

class ConsentScreen extends StatelessWidget {
  final String roomName;
  final VoidCallback onConsent;
  final VoidCallback onDecline;

  const ConsentScreen({
    super.key,
    required this.roomName,
    required this.onConsent,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.mic, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          const Text('Recording Consent'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meeting: $roomName',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This meeting will be recorded for the purpose of generating meeting minutes. '
              'The recording includes audio from all participants. '
              'By consenting, you agree that your voice may be captured and processed.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Do you consent to recording?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onDecline,
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: onConsent,
          child: const Text('I Consent'),
        ),
      ],
    );
  }
}
