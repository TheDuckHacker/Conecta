import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tono de llamada entrante (ring) en bucle.
class CallRingtoneService {
  CallRingtoneService._();
  static final CallRingtoneService instance = CallRingtoneService._();

  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _ready = false;

  bool get isPlaying => _playing;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      // Precargar para que el primer ring no tarde
      await _player.setSource(AssetSource('sounds/ringtone.wav'));
      _ready = true;
    } catch (e) {
      debugPrint('CallRingtone init: $e');
    }
  }

  Future<void> start() async {
    if (_playing) return;
    try {
      await init();
      await HapticFeedback.heavyImpact();
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/ringtone.wav'), volume: 1.0);
      _playing = true;
    } catch (e) {
      debugPrint('CallRingtone start: $e');
      _playing = false;
    }
  }

  Future<void> stop() async {
    if (!_playing && !_ready) return;
    try {
      await _player.stop();
    } catch (_) {}
    _playing = false;
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
