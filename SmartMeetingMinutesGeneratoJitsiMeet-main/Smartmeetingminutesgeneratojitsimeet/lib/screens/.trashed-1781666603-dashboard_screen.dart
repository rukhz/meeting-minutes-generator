// User dashboard: meeting history, search, filters.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_meeting_service.dart';
import 'meeting_minutes_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirestoreMeetingService _meetingService = FirestoreMeetingService();
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uid = auth.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await auth.signOut();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by keyword, date, speaker...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
              ),
              onSubmitted: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _meetingService.meetingsStream(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                final keyword = _searchController.text.trim().toLowerCase();
                var filtered = docs;
                if (keyword.isNotEmpty) {
                  filtered = docs.where((d) {
                    final data = d.data();
                    final text =
                        '${data['title']} ${data['summary']} ${data['room_name']} ${(data['participants'] as List?)?.map((p) => p['name']).join(' ')}'
                            .toLowerCase();
                    return text.contains(keyword);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.meeting_room, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No meetings yet',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final doc = filtered[i];
                    final data = doc.data();
                    final status = data['status'] as String? ?? '';
                    final title = data['title'] as String? ?? data['room_name'] as String? ?? 'Meeting';
                    final createdAt = data['created_at'] as Timestamp?;
                    final dateStr = createdAt != null
                        ? '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}'
                        : '';
                    final hasMinutes = status == 'completed' &&
                        (data['summary'] != null || (data['transcript'] as List?)?.isNotEmpty == true);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _statusColor(status),
                          child: Icon(_statusIcon(status), color: Colors.white, size: 20),
                        ),
                        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('$dateStr • ${_statusLabel(status)}'),
                        trailing: hasMinutes
                            ? IconButton(
                                icon: const Icon(Icons.summarize),
                                onPressed: () => _openMinutes(context, data),
                              )
                            : null,
                        onTap: hasMinutes ? () => _openMinutes(context, data) : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red.shade700;
      case 'live':
        return Colors.blue.shade700;
      case 'recording':
      case 'processing':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'failed':
        return Icons.error;
      case 'live':
        return Icons.play_circle_fill;
      case 'recording':
        return Icons.mic;
      case 'processing':
        return Icons.hourglass_empty;
      default:
        return Icons.schedule;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      case 'live':
        return 'Live';
      case 'recording':
        return 'Recording';
      case 'processing':
        return 'Processing';
      case 'bot_joining':
        return 'Bot joining';
      default:
        return 'Created';
    }
  }

  void _openMinutes(BuildContext context, Map<String, dynamic> data) {
    final nested = data['minutes'];
    final source = nested is Map<String, dynamic>
        ? nested
        : (nested is Map ? Map<String, dynamic>.from(nested) : data);

    final minutes = {
      'meeting_date': source['meeting_date'] ?? data['meeting_date'] ?? '',
      'participants': source['participants'] ?? data['participants'] ?? [],
      'topics': source['topics'] ?? data['topics'] ?? [],
      'decisions': source['decisions'] ?? data['decisions'] ?? [],
      'action_items': source['action_items'] ?? data['action_items'] ?? [],
      'summary': source['summary'] ?? data['summary'] ?? '',
      'transcript': source['transcript'] ?? data['transcript'] ?? [],
    };
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MeetingMinutesScreen(minutes: minutes),
      ),
    );
  }
}
