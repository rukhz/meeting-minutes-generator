import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../services/jitsi_service.dart';
import '../services/firebase_db_service.dart';
import '../services/firebase_storage_service.dart';
import '../services/recording_service.dart';
import '../services/audio_player_service.dart';
import '../models/meeting.dart';
import 'meeting_minutes_screen.dart';

class MeetingHomePage extends StatefulWidget {
  final bool scrollToRecordings;
  final User? currentUser;

  const MeetingHomePage({super.key, this.scrollToRecordings = false, this.currentUser});

  @override
  State<MeetingHomePage> createState() => _MeetingHomePageState();

  static Route<dynamic> route({bool scrollToRecordings = false, User? currentUser}) {
    return MaterialPageRoute(
      builder: (_) => MeetingHomePage(scrollToRecordings: scrollToRecordings, currentUser: currentUser),
    );
  }
}

class _MeetingHomePageState extends State<MeetingHomePage> with WidgetsBindingObserver {
  final JitsiService _jitsiService = JitsiService();
  final RecordingService _recordingService = RecordingService();
  final AudioPlayerService _audioPlayerService = AudioPlayerService();
  final FirebaseDbService _firebaseDb = FirebaseDbService();
  final FirebaseStorageService _firebaseStorage = FirebaseStorageService();
  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _meetingLinkController = TextEditingController();
  final TextEditingController _serverUrlController = TextEditingController(text: AppConfig.botServerUrl);
  final TextEditingController _backendUrlController = TextEditingController(text: AppConfig.minutesBackendUrl);
  final TextEditingController _userNameController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Meeting> _meetings = [];
  bool _isRecording = false;
  String? _currentRoomName;
  bool _botRecordingEnabled = false;
  bool _openInJitsiApp = false;
  bool _isDetectingServer = false;
  bool _isDetectingBackend = false;
  String? _generatingMinutesMeetingId;

  static const Color _headerBlue = Color(0xFF2196F3);
  static const Color _lightBg = Color(0xFFE3F2FD);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMeetings();
    if (widget.scrollToRecordings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          if (_isRecording && _currentRoomName != null) {
            final roomName = _currentRoomName!;
            if (mounted) setState(() { _isRecording = false; _currentRoomName = null; });
            _autoStopAndDownloadRecording(roomName);
          } else {
            if (mounted) setState(() { _isRecording = false; _currentRoomName = null; });
            _loadMeetings();
          }
        } catch (e) {
          debugPrint('Lifecycle resumed handler error: $e');
          if (mounted) _loadMeetings();
        }
      });
    }
  }

  Future<void> _autoDetectBotServer() async {
    if (_isDetectingServer) return;
    setState(() => _isDetectingServer = true);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scanning local network for bot server...'), duration: Duration(seconds: 2)));
    try {
      final found = await _recordingService.autoDetectServerUrl(tryFirst: [AppConfig.botServerUrl]);
      if (!mounted) return;
      if (found != null) {
        setState(() => _serverUrlController.text = found);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Found bot server: $found'), backgroundColor: Colors.green, duration: const Duration(seconds: 3)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No bot server found. Start server on PC and keep same Wi-Fi.'), backgroundColor: Colors.orange, duration: Duration(seconds: 4)));
      }
    } finally { if (mounted) setState(() => _isDetectingServer = false); }
  }

  Future<void> _autoDetectBackendServer() async {
    if (_isDetectingBackend) return;
    setState(() => _isDetectingBackend = true);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scanning local network for minutes backend...'), duration: Duration(seconds: 2)));
    try {
      String? found;
      final botRaw = _serverUrlController.text.trim();
      if (botRaw.isNotEmpty) {
        String toParse = botRaw;
        if (!toParse.startsWith('http://') && !toParse.startsWith('https://')) toParse = 'http://$toParse';
        try {
          final botUri = Uri.parse(toParse);
          if (botUri.host.isNotEmpty && botUri.host != 'localhost' && botUri.host != '127.0.0.1') {
            final candidate = '${botUri.scheme}://${botUri.host}:5000';
            final ok = await _recordingService.checkEndpointReachable(candidate, endpointPath: '/api/health');
            if (ok) found = candidate;
          }
        } catch (_) {}
      }
      found ??= await _recordingService.autoDetectServerUrl(port: 5000, healthPath: '/api/health', tryFirst: [AppConfig.minutesBackendUrl]);
      found ??= await _recordingService.autoDetectServerUrl(port: 5000, healthPath: '/', tryFirst: [AppConfig.minutesBackendUrl]);
      if (!mounted) return;
      if (found != null) {
        setState(() => _backendUrlController.text = found!);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Found backend: $found'), backgroundColor: Colors.green, duration: const Duration(seconds: 3)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No backend found. Start Flask on PC and keep same Wi-Fi.'), backgroundColor: Colors.orange, duration: Duration(seconds: 4)));
      }
    } finally { if (mounted) setState(() => _isDetectingBackend = false); }
  }

  Future<void> _testServerConnection() async {
    final url = _serverUrlController.text.trim();
    if (url.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter Server URL first'))); return; }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Testing connection…'), duration: Duration(seconds: 2)));
    final ok = await _recordingService.checkServerReachable(url);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server reachable – recording can start'), backgroundColor: Colors.green, duration: Duration(seconds: 3)));
    } else {
      final serverUrl = _serverUrlController.text.trim();
      final base = serverUrl.replaceFirst(RegExp(r'/$'), '');
      final healthUrl = base.isEmpty ? null : '$base/api/health';
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Cannot reach bot server'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('On your PC:'), const SizedBox(height: 8),
          const Text('1. Open project folder → server'), const Text('2. Double‑click RUN_BOT_SERVER_EVERYTHING.bat'),
          const Text('3. Copy the URL it shows into this app'), const Text('4. Phone and PC on same Wi‑Fi'),
          const SizedBox(height: 12), Text('Server URL: $serverUrl', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8), const Text('Or turn off "Bot recording" to join meetings without recording.'),
        ])),
        actions: [
          if (healthUrl != null && healthUrl.startsWith('http')) TextButton(onPressed: () async { Navigator.pop(ctx); try { await launchUrl(Uri.parse(healthUrl), mode: LaunchMode.externalApplication); } catch (_) {} }, child: const Text('Open in browser')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ));
    }
  }

  Future<void> _loadMeetings() async {
    final recordings = await _recordingService.getRecordings();
    final meetings = <Meeting>[];
    for (final file in recordings) {
      final fileName = path.basename(file.path);
      final baseName = fileName.startsWith('recording_') ? fileName.replaceFirst('recording_', '').split('.').first : '';
      final meetingId = baseName.isNotEmpty ? baseName : const Uuid().v4();
      List<Map<String, String>>? participants;
      if (baseName.isNotEmpty) {
        try {
          final pf = File('${path.dirname(file.path)}/recording_$baseName.participants.json');
          if (await pf.exists()) {
            final list = jsonDecode(await pf.readAsString()) as List<dynamic>?;
            if (list != null && list.isNotEmpty) participants = list.map((e) => (e as Map<dynamic, dynamic>).map((k, v) => MapEntry(k.toString(), (v?.toString() ?? '')))).toList();
          }
        } catch (_) {}
      }
      meetings.add(Meeting(id: meetingId, roomName: meetingId, createdAt: file.lastModifiedSync(), recordingPath: file.path, participants: participants));
    }
    if (mounted) setState(() => _meetings = meetings);
  }

  Future<void> _saveParticipantsForRecording(String meetingId, String recordingPath, List<Map<String, String>> participants) async {
    if (participants.isEmpty) return;
    try { await File('${path.dirname(recordingPath)}/recording_$meetingId.participants.json').writeAsString(jsonEncode(participants)); } catch (_) {}
  }

  /// Save minutes and MP4 recording to Firebase (Realtime DB + Storage) when user is logged in.
  Future<void> _saveToFirebaseIfLoggedIn({
    required String meetingId,
    required String roomName,
    required Map<String, dynamic> minutes,
    String? localMp4Path,
    List<Map<String, String>>? participants,
  }) async {
    final user = widget.currentUser ?? FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String? recordingUrl;
    if (localMp4Path != null && localMp4Path.toLowerCase().endsWith('.mp4')) {
      try {
        recordingUrl = await _firebaseStorage.uploadRecording(
          localFilePath: localMp4Path,
          uid: user.uid,
          meetingId: meetingId,
        );
      } catch (e) {
        debugPrint('Firebase Storage upload failed: $e');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not upload recording: $e'), backgroundColor: Colors.orange));
        return;
      }
    }
    try {
      await _firebaseDb.saveMeeting(
        uid: user.uid,
        meetingId: meetingId,
        roomName: roomName,
        minutes: minutes,
        recordingStorageUrl: recordingUrl,
        participants: participants,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to cloud'), backgroundColor: Colors.green));
    } catch (e) {
      debugPrint('Firebase DB save failed: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save to cloud: $e'), backgroundColor: Colors.orange));
    }
  }

  Future<void> _createMeeting() async {
    try {
      final roomName = _roomNameController.text.isNotEmpty ? _roomNameController.text : _jitsiService.generateRoomName();
      final meeting = Meeting(id: const Uuid().v4(), roomName: roomName, serverUrl: _serverUrlController.text.isNotEmpty ? _serverUrlController.text : null, createdAt: DateTime.now());
      setState(() { _meetings.add(meeting); _currentRoomName = roomName; });
      await _recordingService.requestPermissions();
      if (_botRecordingEnabled) {
        final serverUrlRaw = _serverUrlController.text.trim().isNotEmpty ? _serverUrlController.text.trim() : RecordingService.defaultServerUrl;
        if (!serverUrlRaw.contains('localhost') && !serverUrlRaw.contains('127.0.0.1')) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connecting to bot server…'), duration: Duration(seconds: 3)));
          try {
            final result = await _recordingService.startRecording(roomName: roomName, serverUrl: serverUrlRaw, meetingId: meeting.id, backendBaseUrl: _backendUrlController.text.trim().isNotEmpty ? _backendUrlController.text.trim() : null);
            if (result != null) {
              setState(() => _isRecording = true);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recording started – bot is joining'), backgroundColor: Colors.green));
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server did not start recording.'), backgroundColor: Colors.orange));
            }
          } catch (e) {
            debugPrint('Warning: Could not start recording: $e');
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().length > 80 ? '${e.toString().substring(0, 80)}…' : e.toString()), backgroundColor: Colors.red, duration: const Duration(seconds: 8)));
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠ Use PC IP or turn off Bot recording'), backgroundColor: Colors.orange));
        }
      }
      await _jitsiService.joinMeeting(roomName: roomName, serverUrl: null, userDisplayName: _userNameController.text.isNotEmpty ? _userNameController.text : 'User', audioMuted: false, videoMuted: false, useJitsiApp: _openInJitsiApp);
    } catch (e) {
      debugPrint('Error creating meeting: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      setState(() { _isRecording = false; _currentRoomName = null; });
    }
  }

  Future<void> _stopRecording() async {
    if (_currentRoomName == null) return;
    Map<String, dynamic>? stopResult;
    try {
      stopResult = await _recordingService.stopRecording(roomName: _currentRoomName!, serverUrl: _serverUrlController.text.isNotEmpty ? _serverUrlController.text : RecordingService.defaultServerUrl, participants: _jitsiService.getParticipants().map((p) => p.toJson()).toList(), backendBaseUrl: _backendUrlController.text.trim().isNotEmpty ? _backendUrlController.text.trim() : null);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.orange));
      return;
    }
    final recordingUrl = stopResult['recordingUrl'] as String?;
    final minutes = stopResult['minutes'] as Map<String, dynamic>?;
    if (minutes != null && minutes.isNotEmpty && mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => MeetingMinutesScreen(minutes: minutes)));
    }
    if (recordingUrl != null && recordingUrl.isNotEmpty) {
      final meeting = _meetings.firstWhere((m) => m.roomName == _currentRoomName, orElse: () => Meeting(id: const Uuid().v4(), roomName: _currentRoomName!, createdAt: DateTime.now()));
      final filePath = await _recordingService.downloadRecording(recordingUrl: recordingUrl, meetingId: meeting.id);
      if (filePath != null) {
        final participants = _jitsiService.getParticipants().map((p) => p.toJson()).toList();
        if (participants.isNotEmpty) await _saveParticipantsForRecording(meeting.id, filePath, participants);
        setState(() { final i = _meetings.indexWhere((m) => m.roomName == _currentRoomName); if (i != -1) _meetings[i] = _meetings[i].copyWith(recordingPath: filePath, participants: participants.isNotEmpty ? participants : null); });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recording saved!')));
        if (minutes != null && minutes.isNotEmpty) {
          await _saveToFirebaseIfLoggedIn(meetingId: meeting.id, roomName: meeting.roomName, minutes: minutes, localMp4Path: filePath.toLowerCase().endsWith('.mp4') ? filePath : null, participants: participants.isNotEmpty ? participants : null);
        }
      }
    }
    setState(() { _isRecording = false; _currentRoomName = null; });
    await _loadMeetings();
  }

  Future<void> _autoStopAndDownloadRecording(String roomName) async {
    try {
      final serverUrl = _serverUrlController.text.isNotEmpty ? _serverUrlController.text : RecordingService.defaultServerUrl;
      if (serverUrl.contains('localhost') || serverUrl.contains('127.0.0.1')) { await _loadMeetings(); return; }
      Map<String, dynamic>? stopResult;
      String? recordingUrl;
      try {
        stopResult = await _recordingService.stopRecording(roomName: roomName, serverUrl: serverUrl, participants: _jitsiService.getParticipants().map((p) => p.toJson()).toList(), backendBaseUrl: _backendUrlController.text.trim().isNotEmpty ? _backendUrlController.text.trim() : null);
        recordingUrl = stopResult['recordingUrl'] as String?;
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not stop server recording.'), backgroundColor: Colors.orange)); await _loadMeetings(); return; }
      if (recordingUrl != null && recordingUrl.isNotEmpty) {
        final meeting = _meetings.firstWhere((m) => m.roomName == roomName, orElse: () => Meeting(id: const Uuid().v4(), roomName: roomName, createdAt: DateTime.now()));
        final filePath = await _recordingService.downloadRecording(recordingUrl: recordingUrl, meetingId: meeting.id);
        if (filePath != null && mounted) {
          final participants = _jitsiService.getParticipants().map((p) => p.toJson()).toList();
          if (participants.isNotEmpty) await _saveParticipantsForRecording(meeting.id, filePath, participants);
          setState(() { final i = _meetings.indexWhere((m) => m.roomName == roomName); if (i != -1 && participants.isNotEmpty) _meetings[i] = _meetings[i].copyWith(participants: participants); });
          final minutesMap = (stopResult['minutes'] is Map) ? Map<String, dynamic>.from(stopResult['minutes']) : null;
          if (minutesMap != null && minutesMap.isNotEmpty) {
            if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => MeetingMinutesScreen(minutes: minutesMap)));
            await _saveToFirebaseIfLoggedIn(meetingId: meeting.id, roomName: meeting.roomName, minutes: minutesMap, localMp4Path: filePath.toLowerCase().endsWith('.mp4') ? filePath : null, participants: participants.isNotEmpty ? participants : null);
          } else {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recording saved!'), backgroundColor: Colors.green));
          }
        }
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.orange)); }
    finally { if (mounted) await _loadMeetings(); }
  }

  Future<void> _joinViaLink() async {
    try {
      final link = _meetingLinkController.text.trim();
      if (link.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a meeting link'))); return; }
      final roomName = _jitsiService.extractRoomNameFromUrl(link);
      if (roomName == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid meeting link'))); return; }
      final jitsiServerUrl = _jitsiService.extractServerUrlFromUrl(link);
      final recordingServerUrl = _serverUrlController.text.trim().isNotEmpty ? _serverUrlController.text.trim() : RecordingService.defaultServerUrl;
      if (_botRecordingEnabled && !recordingServerUrl.contains('localhost') && !recordingServerUrl.contains('127.0.0.1')) {
        try {
          _meetings.add(Meeting(id: const Uuid().v4(), roomName: roomName, createdAt: DateTime.now()));
          await _recordingService.startRecording(roomName: roomName, serverUrl: recordingServerUrl, meetingId: _meetings.last.id, backendBaseUrl: _backendUrlController.text.trim().isNotEmpty ? _backendUrlController.text.trim() : null);
          setState(() { _isRecording = true; _currentRoomName = roomName; });
        } catch (_) {}
      }
      await _jitsiService.joinMeeting(roomName: roomName, serverUrl: jitsiServerUrl, userDisplayName: _userNameController.text.isNotEmpty ? _userNameController.text : 'User', audioMuted: false, videoMuted: false, useJitsiApp: _openInJitsiApp);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)); }
  }

  Future<void> _generateMinutes(Meeting meeting) async {
    if (meeting.recordingPath == null || meeting.recordingPath!.isEmpty) return;
    final backendUrl = _backendUrlController.text.trim();
    if (backendUrl.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter Minutes backend URL'))); return; }
    setState(() => _generatingMinutesMeetingId = meeting.id);
    try {
      final response = await _recordingService.uploadForMinutes(recordingPath: meeting.recordingPath!, meetingId: meeting.id, participants: meeting.participants ?? [], backendUrl: backendUrl);
      final minutes = response['minutes'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() => _generatingMinutesMeetingId = null);
      if (minutes == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No minutes returned'), backgroundColor: Colors.orange)); return; }
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => MeetingMinutesScreen(minutes: minutes)));
      await _saveToFirebaseIfLoggedIn(meetingId: meeting.id, roomName: meeting.roomName, minutes: minutes, localMp4Path: meeting.recordingPath, participants: meeting.participants);
    } catch (e) {
      if (!mounted) return;
      setState(() => _generatingMinutesMeetingId = null);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _playRecording(String? filePath) async {
    if (filePath == null) return;
    try {
      if (!await File(filePath).exists()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File not found')));
        return;
      }
      if (_audioPlayerService.currentFilePath == filePath && _audioPlayerService.isPlaying) {
        await _audioPlayerService.pause();
      } else {
        await _audioPlayerService.playFile(filePath);
      }
      setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _headerBlue,
        foregroundColor: Colors.white,
        title: const Text('Smart Meeting Minutes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: Container(
        color: _lightBg,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(controller: _userNameController, decoration: const InputDecoration(labelText: 'Your Name', border: OutlineInputBorder(), filled: true)),
                      const SizedBox(height: 16),
                      TextField(controller: _meetingLinkController, decoration: const InputDecoration(labelText: 'Meeting Link (e.g., https://meet.jit.si...)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.link), filled: true)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(onPressed: _isRecording ? null : _joinViaLink, icon: const Icon(Icons.login), label: const Text('Join via Link'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.green, foregroundColor: Colors.white)),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      TextField(controller: _roomNameController, decoration: const InputDecoration(labelText: 'Room Name (leave empty to generate)', border: OutlineInputBorder(), filled: true)),
                      const SizedBox(height: 16),
                      Row(children: [Expanded(child: Text('Bot recording (needs server on PC)', style: Theme.of(context).textTheme.bodyLarge)), Switch(value: _botRecordingEnabled, onChanged: _isRecording ? null : (v) => setState(() => _botRecordingEnabled = v))]),
                      const SizedBox(height: 8),
                      Row(children: [Expanded(child: Text('Open in Jitsi Meet app (if installed)', style: Theme.of(context).textTheme.bodyLarge)), Switch(value: _openInJitsiApp, onChanged: _isRecording ? null : (v) => setState(() => _openInJitsiApp = v))]),
                      const SizedBox(height: 8),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: TextField(controller: _serverUrlController, decoration: const InputDecoration(labelText: 'Server URL (for bot)', hintText: 'e.g. http://192.168.1.5:3000', border: OutlineInputBorder(), filled: true), enabled: _botRecordingEnabled)), const SizedBox(width: 8), OutlinedButton(onPressed: (_isRecording || !_botRecordingEnabled || _isDetectingServer) ? null : _autoDetectBotServer, child: _isDetectingServer ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Auto')), const SizedBox(width: 8), OutlinedButton(onPressed: (_isRecording || !_botRecordingEnabled) ? null : _testServerConnection, child: const Text('Test'))]),
                      if (!_botRecordingEnabled) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Meetings will start without server recording.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey))),
                      const SizedBox(height: 16),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: TextField(controller: _backendUrlController, decoration: const InputDecoration(labelText: 'Minutes backend URL (Flask)', hintText: 'e.g. http://192.168.1.5:5000', border: OutlineInputBorder(), filled: true))), const SizedBox(width: 8), OutlinedButton(onPressed: _isDetectingBackend ? null : _autoDetectBackendServer, child: _isDetectingBackend ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Auto'))]),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(onPressed: _isRecording ? null : _createMeeting, icon: const Icon(Icons.video_call), label: const Text('Create & Join Meeting'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: _headerBlue, foregroundColor: Colors.white)),
                      if (_isRecording) ...[const SizedBox(height: 16), ElevatedButton.icon(onPressed: _stopRecording, icon: const Icon(Icons.stop), label: const Text('Stop Recording'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.red, foregroundColor: Colors.white))],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Recordings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMeetings, tooltip: 'Refresh')]),
              const SizedBox(height: 16),
              _meetings.isEmpty ? const Card(child: Padding(padding: EdgeInsets.all(16), child: Center(child: Text('No recordings yet')))) : ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _meetings.length, itemBuilder: (_, i) {
                final m = _meetings[i];
                return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: const Icon(Icons.audiotrack), title: Text('Room: ${m.roomName}'), subtitle: Text(m.createdAt.toString().split('.')[0]), trailing: m.recordingPath != null ? Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_generatingMinutesMeetingId == m.id) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) else IconButton(icon: const Icon(Icons.summarize), onPressed: () => _generateMinutes(m)),
                  IconButton(icon: Icon(_audioPlayerService.currentFilePath == m.recordingPath && _audioPlayerService.isPlaying ? Icons.pause : Icons.play_arrow), onPressed: () => _playRecording(m.recordingPath)),
                ]) : null));
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _audioPlayerService.dispose();
    _roomNameController.dispose();
    _meetingLinkController.dispose();
    _serverUrlController.dispose();
    _backendUrlController.dispose();
    _userNameController.dispose();
    super.dispose();
  }
}
