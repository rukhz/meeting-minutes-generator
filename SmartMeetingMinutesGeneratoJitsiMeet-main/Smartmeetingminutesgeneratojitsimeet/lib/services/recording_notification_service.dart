import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shows a persistent notification when recording is active so the user can tap
/// to return to the app and stop recording (e.g. when meeting was opened in external Jitsi app).
class RecordingNotificationService {
  static const int _recordingNotificationId = 9001;
  static const String _channelId = 'recording_channel';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _plugin.initialize(initSettings);
    await _createChannel();
    _initialized = true;
  }

  Future<void> _createChannel() async {
    if (Platform.isAndroid) {
      try {
        final enabled = await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled() ?? false;
        if (!enabled) await Permission.notification.request();
      } catch (_) {}
    }
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Recording',
        description: 'Shows when a meeting is being recorded. Tap to open app and stop recording.',
        importance: Importance.high,
        playSound: false,
      ),
    );
  }

  /// Call when recording starts and user may leave the app (e.g. joining meeting).
  /// Tapping the notification brings the app to foreground so they can tap Stop Recording.
  Future<void> showRecordingActive() async {
    if (Platform.isAndroid) {
      try {
        await Permission.notification.request();
      } catch (_) {}
    }
    await init();
    final android = AndroidNotificationDetails(
      _channelId,
      'Recording',
      channelDescription: 'Tap to open app and stop recording',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      visibility: NotificationVisibility.public,
    );
    await _plugin.show(
      _recordingNotificationId,
      'Recording in progress',
      'Tap to open app and stop recording',
      NotificationDetails(android: android),
    );
  }

  /// Call when recording has stopped.
  Future<void> cancelRecordingNotification() async {
    await _plugin.cancel(_recordingNotificationId);
  }
}
