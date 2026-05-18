import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioPlayerService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentFilePath;
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;
  String? get currentFilePath => _currentFilePath;

  Future<void> playFile(String filePath) async {
    try {
      if (_currentFilePath == filePath && _isPlaying) {
        await pause();
        return;
      }

      if (_currentFilePath != filePath) {
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(filePath));
        _currentFilePath = filePath;
        _isPlaying = true;
      } else {
        await _audioPlayer.resume();
        _isPlaying = true;
      }
    } catch (e) {
      debugPrint('Error playing file: $e');
      rethrow;
    }
  }

  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      _isPlaying = false;
    } catch (e) {
      debugPrint('Error pausing: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _isPlaying = false;
      _currentFilePath = null;
    } catch (e) {
      debugPrint('Error stopping: $e');
    }
  }

  Future<void> dispose() async {
    await _audioPlayer.dispose();
  }

  Stream<Duration> get onPositionChanged => _audioPlayer.onPositionChanged;
  Stream<Duration> get onDurationChanged => _audioPlayer.onDurationChanged;
  Future<Duration?> getDuration() async {
    try {
      return await _audioPlayer.getDuration();
    } catch (e) {
      return null;
    }
  }

  Future<Duration> getPosition() async {
    try {
      return await _audioPlayer.getCurrentPosition() ?? Duration.zero;
    } catch (e) {
      return Duration.zero;
    }
  }
}

