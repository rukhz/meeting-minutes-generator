import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_config.dart';
import '../services/jitsi_service.dart';
import '../services/flask_bot_service.dart';
import '../services/recording_service.dart';
import 'minutes_text_screen.dart';

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
  final FlaskBotService _flaskBot = FlaskBotService();
  final RecordingService _recordingService = RecordingService();
  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _meetingLinkController = TextEditingController();
  final TextEditingController _flaskUrlController = TextEditingController(text: AppConfig.minutesBackendUrl);
  final TextEditingController _userNameController = TextEditingController();

  bool _isRecording = false;
  String? _currentRoomName;
  bool _isStopping = false;
  bool _isDetectingFlask = false;
  bool _openInJitsiApp = false;
  DateTime? _wentToBackgroundAt;

  static const Color _headerBlue = Color(0xFF2196F3);
  static const Color _lightBg = Color(0xFFE3F2FD);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _testFlaskUrl() async {
    final flaskUrl = _flaskUrlController.text.trim();
    if (flaskUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter Flask URL first')));
      return;
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Testing...'), duration: Duration(seconds: 1)));
    final result = await _flaskBot.checkStatus(flaskUrl: flaskUrl);
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Flask server reachable'), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${result['error']}'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
      );
    }
  }

  Future<void> _autoDetectFlask() async {
    if (_isDetectingFlask) return;
    setState(() => _isDetectingFlask = true);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scanning for Flask...'), duration: Duration(seconds: 2)));
    try {
      final found = await _recordingService.autoDetectServerUrl(
        port: 5000,
        healthPath: '/api/bot/status',
        tryFirst: [AppConfig.minutesBackendUrl],
      ).timeout(const Duration(seconds: 15), onTimeout: () => null);
      if (!mounted) return;
      if (found != null && found.isNotEmpty) {
        setState(() => _flaskUrlController.text = found);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Found: $found'), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Not found. Run app.py with host 0.0.0.0, enter PC IP manually (e.g. http://192.168.1.5:5000), same Wi‑Fi.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 6),
        ));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan timed out. Enter Flask URL manually.'), backgroundColor: Colors.orange));
    } finally {
      if (mounted) setState(() => _isDetectingFlask = false);
    }
  }

  /// Called when user leaves in-app Jitsi meeting. Auto-stop bot and fetch minutes.
  void _onConferenceEnded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _stopMeeting();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _wentToBackgroundAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      // User returned from Jitsi (external app or in-app closed): auto-stop and fetch minutes
      if (_isRecording && !_isStopping && _currentRoomName != null) {
        final elapsed = _wentToBackgroundAt != null
            ? DateTime.now().difference(_wentToBackgroundAt!).inSeconds
            : 999;
        if (elapsed >= 2) {
          _wentToBackgroundAt = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _stopMeeting();
          });
        }
      }
      _wentToBackgroundAt = null;
    }
  }

  Future<void> _createMeeting() async {
    final roomName = _roomNameController.text.trim().isNotEmpty
        ? _roomNameController.text.trim()
        : _jitsiService.generateRoomName();
    final flaskUrl = _flaskUrlController.text.trim();
    if (flaskUrl.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Flask server URL (e.g. http://PC_IP:5000)'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() { _currentRoomName = roomName; });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Calling Flask: Start meeting...')));

    final joinResult = await _flaskBot.join(
      room: roomName,
      displayName: 'MeetingBot',
      flaskUrl: flaskUrl,
    );

    if (!mounted) return;
    if (joinResult['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(joinResult['error']?.toString() ?? 'Bot join failed'), backgroundColor: Colors.red),
      );
      setState(() { _currentRoomName = null; });
      return;
    }

    setState(() => _isRecording = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bot joining. Opening Jitsi...'), backgroundColor: Colors.green));

    await _jitsiService.joinMeeting(
      roomName: roomName,
      serverUrl: null,
      userDisplayName: _userNameController.text.trim().isNotEmpty ? _userNameController.text : 'User',
      audioMuted: false,
      videoMuted: false,
      useJitsiApp: _openInJitsiApp,
      onConferenceTerminated: () => _onConferenceEnded(),
    );
  }

  Future<void> _stopMeeting() async {
    if (_currentRoomName == null || _isStopping) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_currentRoomName == null ? 'No active meeting' : 'Stopping…'), duration: const Duration(seconds: 2)),
        );
      }
      return;
    }
    final flaskUrl = _flaskUrlController.text.trim();
    if (flaskUrl.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter Flask URL first')));
      return;
    }

    setState(() => _isStopping = true);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stopping meeting and generating minutes…')));

    try {
      final leaveResult = await _flaskBot.leave(flaskUrl: flaskUrl);
      if (!mounted) return;
      final leaveError = leaveResult['error']?.toString() ?? '';
      final botAlreadyLeft = leaveError.toLowerCase().contains('not in a meeting') || leaveError.contains('not in meeting');

      if (leaveResult['success'] != true && !botAlreadyLeft) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(leaveError.isNotEmpty ? leaveError : 'Stop failed'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
        setState(() { _isStopping = false; _isRecording = false; _currentRoomName = null; });
        return;
      }
      if (botAlreadyLeft && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meeting already ended. Fetching minutes…'), duration: Duration(seconds: 3)),
        );
      }

      // Transcription can take 1–2 minutes. Poll for minutes every 5s, up to 2 min.
      String? minutesText;
      for (int i = 0; i < 24; i++) {
        await Future.delayed(const Duration(seconds: 5));
        if (!mounted) return;
        if (mounted && i > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Generating minutes… ${(i + 1) * 5}s'), duration: const Duration(seconds: 2)),
          );
        }
        minutesText = await _flaskBot.fetchMinutes(flaskUrl: flaskUrl);
        if (!mounted) return;
        if (minutesText != null && minutesText.trim().isNotEmpty) break;
      }

      if (!mounted) return;
      setState(() { _isStopping = false; _isRecording = false; _currentRoomName = null; });

      if (minutesText != null && minutesText.trim().isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MinutesTextScreen(minutesText: minutesText!)),
        );
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Minutes displayed.'), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Minutes not ready. Check Flask terminal; transcription may take 1–2 minutes. Try again later.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 8),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('_stopMeeting error: $e $st');
      if (mounted) {
        setState(() { _isStopping = false; _isRecording = false; _currentRoomName = null; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 6)),
        );
      }
    }
  }

  Future<void> _joinViaLink() async {
    final link = _meetingLinkController.text.trim();
    if (link.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a meeting link')));
      return;
    }
    final roomName = _jitsiService.extractRoomNameFromUrl(link);
    if (roomName == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid meeting link')));
      return;
    }
    final jitsiServerUrl = _jitsiService.extractServerUrlFromUrl(link);
    await _jitsiService.joinMeeting(
      roomName: roomName,
      serverUrl: jitsiServerUrl,
      userDisplayName: _userNameController.text.trim().isNotEmpty ? _userNameController.text : 'User',
      audioMuted: false,
      videoMuted: false,
      useJitsiApp: _openInJitsiApp,
      onConferenceTerminated: () => _onConferenceEnded(),
    );
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
                      TextField(
                        controller: _userNameController,
                        decoration: const InputDecoration(labelText: 'Your Name', border: OutlineInputBorder(), filled: true),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _meetingLinkController,
                        decoration: const InputDecoration(
                          labelText: 'Meeting Link (optional)',
                          hintText: 'https://meet.jit.si/room-name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.link),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isRecording ? null : _joinViaLink,
                        icon: const Icon(Icons.login),
                        label: const Text('Join via Link'),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.green, foregroundColor: Colors.white),
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _flaskUrlController,
                              decoration: const InputDecoration(
                                labelText: 'Flask Server URL (app.py)',
                                hintText: 'e.g. http://192.168.1.5:5000',
                                border: OutlineInputBorder(),
                                filled: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: (_isRecording || _isDetectingFlask) ? null : _autoDetectFlask,
                            child: _isDetectingFlask
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Auto'),
                          ),
                          const SizedBox(width: 4),
                          OutlinedButton(
                            onPressed: (_isRecording || _isDetectingFlask) ? null : _testFlaskUrl,
                            child: const Text('Test'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _roomNameController,
                        decoration: const InputDecoration(
                          labelText: 'Room Name (leave empty to generate)',
                          border: OutlineInputBorder(),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: Text('Open in Jitsi Meet app', style: Theme.of(context).textTheme.bodyLarge)),
                          Switch(value: _openInJitsiApp, onChanged: _isRecording ? null : (v) => setState(() => _openInJitsiApp = v)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: (_isRecording || _isStopping) ? null : _createMeeting,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start Meeting'),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: _headerBlue, foregroundColor: Colors.white),
                      ),
                      if (_isRecording) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _isStopping ? null : _stopMeeting,
                          icon: _isStopping
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.stop),
                          label: Text(_isStopping ? 'Stopping…' : 'Stop Meeting'),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.red, foregroundColor: Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    _meetingLinkController.dispose();
    _flaskUrlController.dispose();
    _userNameController.dispose();
    super.dispose();
  }
}
