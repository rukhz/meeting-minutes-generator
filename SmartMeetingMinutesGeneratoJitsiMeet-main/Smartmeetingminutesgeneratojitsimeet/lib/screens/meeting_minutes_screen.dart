import 'package:flutter/material.dart';

/// Displays meeting minutes from the Flask API: transcript, summary, participants,
/// topics, decisions, action items. Expects the mandatory backend JSON format.
class MeetingMinutesScreen extends StatelessWidget {
  final Map<String, dynamic> minutes;

  const MeetingMinutesScreen({super.key, required this.minutes});

  @override
  Widget build(BuildContext context) {
    final nested = minutes['minutes'];
    final payload = nested is Map<String, dynamic>
        ? nested
        : (nested is Map ? Map<String, dynamic>.from(nested) : minutes);

    final transcriptionError = (minutes['transcription_error'] as String?)?.trim() ?? '';
    final transcriptionDone = minutes['transcription_done'] == true;

    final summary = payload['summary'] as String? ?? '';
    final transcript = payload['transcript'] as List<dynamic>? ?? [];
    final participants = _resolveParticipants(payload['participants'] as List<dynamic>? ?? [], transcript);
    final topics = payload['topics'] as List<dynamic>? ?? [];
    final decisions = payload['decisions'] as List<dynamic>? ?? [];
    final actionItems = payload['action_items'] as List<dynamic>? ?? [];
    final meetingDate = payload['meeting_date'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting Minutes'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (meetingDate.isNotEmpty) _buildDateHeader(context, meetingDate),
            if (transcriptionError.isNotEmpty)
              _buildSection(context, 'Transcription', _buildInfoCard(
                transcriptionError,
                color: Colors.orange.shade100,
                textColor: Colors.orange.shade900,
              )),
            if (!transcriptionDone && transcript.isEmpty && transcriptionError.isEmpty)
              _buildSection(context, 'Transcription', _buildInfoCard(
                'No speech detected in this recording. Try speaking closer to the mic and ensure bot audio capture is enabled.',
                color: Colors.orange.shade100,
                textColor: Colors.orange.shade900,
              )),
            if (summary.isNotEmpty) _buildSection(context, 'Summary', _buildSummaryCard(summary)),
            _buildSection(context, 'Participants', _buildParticipants(participants)),
            _buildSection(context, 'Transcript', _buildTranscript(transcript)),
            if (topics.isNotEmpty) _buildSection(context, 'Topics', _buildTopics(topics)),
            if (decisions.isNotEmpty) _buildSection(context, 'Decisions', _buildDecisions(decisions)),
            if (actionItems.isNotEmpty) _buildSection(context, 'Action Items', _buildActionItems(actionItems)),
          ],
        ),
      ),
    );
  }

  List<dynamic> _resolveParticipants(List<dynamic> participants, List<dynamic> transcript) {
    if (participants.isNotEmpty) return participants;

    final seen = <String>{};
    final fromTranscript = <Map<String, String>>[];
    for (final seg in transcript) {
      if (seg is! Map) continue;
      final raw = (seg['speaker'] ?? '').toString().trim();
      if (raw.isEmpty) continue;
      final key = raw.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      fromTranscript.add({'name': raw});
    }
    return fromTranscript;
  }

  Widget _buildDateHeader(BuildContext context, String meetingDate) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        'Date: $meetingDate',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, Widget content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
          ),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String summary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(summary, style: const TextStyle(height: 1.4)),
      ),
    );
  }

  Widget _buildInfoCard(String message, {required Color color, required Color textColor}) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: TextStyle(color: textColor, height: 1.35),
        ),
      ),
    );
  }

  Widget _buildParticipants(List<dynamic> participants) {
    if (participants.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No participants identified.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: participants.map<Widget>((p) {
        final name = (p is Map<String, dynamic>) ? (p['name'] as String? ?? '') : p.toString();
        return Chip(
          avatar: CircleAvatar(
            backgroundColor: Colors.blue.shade100,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: Colors.blue.shade800, fontSize: 12)),
          ),
          label: Text(name),
        );
      }).toList(),
    );
  }

  Widget _buildTranscript(List<dynamic> transcript) {
    if (transcript.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No transcript available.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: transcript.map<Widget>((seg) {
        final map = seg as Map<String, dynamic>;
        final speaker = map['speaker'] as String? ?? 'Speaker';
        final text = map['text'] as String? ?? '';
        final start = map['start'];
        final end = map['end'];
        final timestampStr = map['timestamp'] as String?;
        String time = timestampStr ?? '';
        if (time.isEmpty && start != null && end != null) {
          final s = (start is num) ? start.toDouble() : 0.0;
          final e = (end is num) ? end.toDouble() : 0.0;
          time = '${s.toStringAsFixed(1)}s – ${e.toStringAsFixed(1)}s';
        }
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              speaker + (time.isNotEmpty ? ' ($time)' : ''),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text, style: const TextStyle(height: 1.35)),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTopics(List<dynamic> topics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: topics.map<Widget>((t) {
        final map = t as Map<String, dynamic>;
        final title = map['title'] as String? ?? '';
        final summaryText = map['summary'] as String? ?? '';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(summaryText, style: const TextStyle(height: 1.35)),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDecisions(List<dynamic> decisions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: decisions.map<Widget>((d) {
        final text = (d is Map<String, dynamic>) ? (d['text'] as String? ?? '') : d.toString();
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
            title: Text(text, style: const TextStyle(height: 1.35)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionItems(List<dynamic> actionItems) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: actionItems.map<Widget>((a) {
        final map = a as Map<String, dynamic>;
        final task = map['task'] as String? ?? map['description'] as String? ?? '';
        final owner = map['owner'] as String?;
        final deadline = map['deadline'] as String?;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.assignment_outlined, color: Colors.blue),
            title: Text(task, style: const TextStyle(height: 1.35)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  if (owner != null && owner.toString().isNotEmpty) 'Owner: $owner',
                  if (deadline != null && deadline.toString().isNotEmpty) 'Deadline: $deadline',
                ].join(' • '),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
