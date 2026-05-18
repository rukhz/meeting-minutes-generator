class Meeting {
  final String id;
  final String roomName;
  final String? serverUrl;
  final DateTime createdAt;
  final String? recordingPath;
  /// Jitsi participant list (id, name) for mapping speakers in minutes.
  final List<Map<String, String>>? participants;

  Meeting({
    required this.id,
    required this.roomName,
    this.serverUrl,
    required this.createdAt,
    this.recordingPath,
    this.participants,
  });

  String get jitsiUrl {
    final baseUrl = serverUrl ?? 'https://meet.jit.si';
    return '$baseUrl/$roomName';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'roomName': roomName,
      'serverUrl': serverUrl,
      'createdAt': createdAt.toIso8601String(),
      'recordingPath': recordingPath,
      'participants': participants,
    };
  }

  Meeting copyWith({
    String? id,
    String? roomName,
    String? serverUrl,
    DateTime? createdAt,
    String? recordingPath,
    List<Map<String, String>>? participants,
  }) {
    return Meeting(
      id: id ?? this.id,
      roomName: roomName ?? this.roomName,
      serverUrl: serverUrl ?? this.serverUrl,
      createdAt: createdAt ?? this.createdAt,
      recordingPath: recordingPath ?? this.recordingPath,
      participants: participants ?? this.participants,
    );
  }

  factory Meeting.fromJson(Map<String, dynamic> json) {
    final p = json['participants'];
    List<Map<String, String>>? list;
    if (p is List) {
      list = p
          .map((e) => (e is Map) ? Map<String, String>.from(e.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))) : <String, String>{})
          .where((m) => m.isNotEmpty)
          .toList();
    }
    return Meeting(
      id: json['id'] as String? ?? '',
      roomName: json['roomName'] as String? ?? '',
      serverUrl: json['serverUrl'] as String?,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now() : DateTime.now(),
      recordingPath: json['recordingPath'] as String?,
      participants: list,
    );
  }
}

