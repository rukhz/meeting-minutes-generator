// Meeting status banner: Bot joining | Recording | Processing | Completed.
import 'package:flutter/material.dart';

enum MeetingStatus {
  live,
  botJoining,
  recording,
  processing,
  completed,
  failed,
  none,
}

class MeetingStatusBanner extends StatelessWidget {
  final MeetingStatus status;
  final String? roomName;

  const MeetingStatusBanner({super.key, required this.status, this.roomName});

  static MeetingStatus fromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'live':
        return MeetingStatus.live;
      case 'bot_joining':
        return MeetingStatus.botJoining;
      case 'recording':
        return MeetingStatus.recording;
      case 'processing':
        return MeetingStatus.processing;
      case 'completed':
        return MeetingStatus.completed;
      case 'failed':
        return MeetingStatus.failed;
      default:
        return MeetingStatus.none;
    }
  }

  String get _label {
    switch (status) {
      case MeetingStatus.live:
        return 'Live';
      case MeetingStatus.botJoining:
        return 'Bot joining...';
      case MeetingStatus.recording:
        return 'Recording in progress';
      case MeetingStatus.processing:
        return 'Processing...';
      case MeetingStatus.completed:
        return 'Completed';
      case MeetingStatus.failed:
        return 'Failed';
      case MeetingStatus.none:
        return '';
    }
  }

  IconData get _icon {
    switch (status) {
      case MeetingStatus.live:
        return Icons.play_circle_fill;
      case MeetingStatus.botJoining:
        return Icons.smart_toy_outlined;
      case MeetingStatus.recording:
        return Icons.mic;
      case MeetingStatus.processing:
        return Icons.hourglass_empty;
      case MeetingStatus.completed:
        return Icons.check_circle;
      case MeetingStatus.failed:
        return Icons.error;
      case MeetingStatus.none:
        return Icons.info_outline;
    }
  }

  Color _color(BuildContext context) {
    switch (status) {
      case MeetingStatus.live:
        return Colors.blue.shade700;
      case MeetingStatus.botJoining:
        return Colors.orange.shade700;
      case MeetingStatus.recording:
        return Colors.red.shade700;
      case MeetingStatus.processing:
        return Colors.blue.shade700;
      case MeetingStatus.completed:
        return Colors.green.shade700;
      case MeetingStatus.failed:
        return Colors.red.shade800;
      case MeetingStatus.none:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (status == MeetingStatus.none || _label.isEmpty) {
      return const SizedBox.shrink();
    }
    return Material(
      color: _color(context),
      elevation: 4,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(_icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (roomName != null && roomName!.isNotEmpty)
                      Text(
                        roomName!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (status == MeetingStatus.recording || status == MeetingStatus.processing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
