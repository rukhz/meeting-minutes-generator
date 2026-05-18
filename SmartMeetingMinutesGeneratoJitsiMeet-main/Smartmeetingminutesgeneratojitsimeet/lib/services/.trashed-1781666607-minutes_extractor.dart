// Builds meeting minutes JSON from plain transcript text.

class MinutesExtractor {
  /// Returns a map compatible with MeetingMinutesScreen: meeting_date, participants,
  /// transcript, topics, decisions, action_items, summary.
  static Map<String, dynamic> fromTranscript(String transcriptText) {
    final now = DateTime.now();
    final meetingDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final sentences = _splitSentences(transcriptText.trim());
    final summary = _summary(sentences);
    final transcript = _toTranscriptSegments(transcriptText.trim());
    final topics = _topics(sentences);
    final decisions = _decisions(sentences);
    final actionItems = _actionItems(sentences);

    return {
      'meeting_date': meetingDate,
      'participants': [], // Would need speaker diarization to fill
      'transcript': transcript,
      'topics': topics,
      'decisions': decisions,
      'action_items': actionItems,
      'summary': summary,
    };
  }

  static List<String> _splitSentences(String text) {
    if (text.isEmpty) return [];
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return [];
    final parts = cleaned.split(RegExp(r'(?<=[.!?])\s+'));
    return parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  }

  static String _summary(List<String> sentences, {int max = 5}) {
    if (sentences.isEmpty) return '';
    return sentences.take(max).join(' ');
  }

  static List<Map<String, dynamic>> _toTranscriptSegments(String text) {
    if (text.isEmpty) return [];
    final sentences = _splitSentences(text);
    return sentences
        .map((s) => {
              'speaker': 'Participant',
              'text': s,
              'start': null,
              'end': null,
            })
        .toList();
  }

  static List<Map<String, dynamic>> _topics(List<String> sentences, {int perTopic = 5}) {
    if (sentences.isEmpty) return [];
    final list = <Map<String, dynamic>>[];
    for (var i = 0; i < sentences.length; i += perTopic) {
      final block = sentences.skip(i).take(perTopic).toList();
      final summaryText = block.join(' ').trim();
      if (summaryText.isEmpty) continue;
      list.add({
        'title': 'Topic ${list.length + 1}',
        'summary': summaryText,
      });
    }
    return list;
  }

  static const _decisionCues = [
    'we decided',
    'decision',
    'agreed',
    'approved',
    "let's go with",
    'concluded',
    'agreement',
  ];

  static List<Map<String, dynamic>> _decisions(List<String> sentences) {
    final list = <Map<String, dynamic>>[];
    for (final s in sentences) {
      final lower = s.toLowerCase();
      if (_decisionCues.any((c) => lower.contains(c))) {
        list.add({'text': s});
      }
    }
    return list;
  }

  static const _actionCues = [
    'will ',
    'will do',
    'to do',
    'action item',
    'follow up',
    'need to',
    'needs to',
    'should ',
    'must ',
    'assigned to',
    'by tomorrow',
    'by next week',
    'deadline',
  ];

  static List<Map<String, dynamic>> _actionItems(List<String> sentences) {
    final list = <Map<String, dynamic>>[];
    for (final s in sentences) {
      final lower = s.toLowerCase();
      if (!_actionCues.any((c) => lower.contains(c))) continue;
      final owner = _firstCapitalizedWord(s);
      final deadline = _extractDeadline(s);
      list.add({
        'task': s,
        'description': s,
        'owner': owner,
        'deadline': deadline,
      });
    }
    return list;
  }

  static String? _firstCapitalizedWord(String text) {
    final match = RegExp(r'\b([A-Z][a-zA-Z]+)\b').firstMatch(text);
    return match?.group(1);
  }

  static String? _extractDeadline(String text) {
    final patterns = [
      RegExp(r'by\s+(\w+\s+\d{1,2}(?:st|nd|rd|th)?(?:\s*,?\s*\d{4})?)', caseSensitive: false),
      RegExp(r'by\s+(tomorrow|next\s+week|next\s+month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)', caseSensitive: false),
      RegExp(r'deadline[:\s]+([^.]+)', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) return m.group(1)?.trim();
    }
    return null;
  }
}
