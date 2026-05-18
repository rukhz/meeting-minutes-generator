import 'dart:io';

import 'package:flutter/foundation.dart';

/// App networking defaults for local development.
///
/// You can override these at build/run time with:
/// --dart-define=BOT_SERVER_URL=http://YOUR_PC_IP:3000
/// --dart-define=MINUTES_BACKEND_URL=http://YOUR_PC_IP:5000
/// --dart-define=PC_LAN_IP=YOUR_PC_IP
class AppConfig {
  AppConfig._();

  static const String _botServerOverride =
      String.fromEnvironment('BOT_SERVER_URL', defaultValue: '');
  static const String _minutesBackendOverride =
      String.fromEnvironment('MINUTES_BACKEND_URL', defaultValue: '');
  static const String _pcLanIpOverride =
      String.fromEnvironment('PC_LAN_IP', defaultValue: '');

  static String get _defaultHost {
    if (kIsWeb) return 'localhost';
    if (Platform.isAndroid) {
      final ip = _pcLanIpOverride.trim();
      if (ip.isNotEmpty) return ip;
      return '10.0.2.2';
    }
    return 'localhost';
  }

  /// Bot recording server (Node)
  static String get botServerUrl {
    if (_botServerOverride.trim().isNotEmpty) {
      return _botServerOverride.trim();
    }
    return 'http://$_defaultHost:3000';
  }

  /// Minutes backend (Flask)
  static String get minutesBackendUrl {
    if (_minutesBackendOverride.trim().isNotEmpty) {
      return _minutesBackendOverride.trim();
    }
    return 'http://$_defaultHost:5000';
  }
}
