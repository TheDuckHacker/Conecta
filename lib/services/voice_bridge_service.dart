import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'ai_config.dart';

/// Voz ↔ texto. Render /tts primero; si falla, TTS del dispositivo.
/// No pide ni guarda API keys en el teléfono.
class VoiceBridgeService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();

  bool _speechReady = false;
  bool _listening = false;
  bool _speaking = false;

  bool get isListening => _listening;
  bool get usingElevenLabs => true;

  Future<void> init() async {
    try {
      _speechReady = await _speech.initialize(
        onError: (e) => debugPrint('STT error: $e'),
        onStatus: (s) {
          if (s == 'notListening' || s == 'done') {
            _listening = false;
          }
        },
      );
      await _tts.setLanguage('es-ES');
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _player.setReleaseMode(ReleaseMode.stop);
    } catch (e) {
      debugPrint('VoiceBridge init: $e');
    }
  }

  Future<void> startListening({
    required void Function(String text, bool finalResult) onResult,
  }) async {
    if (!_speechReady) await init();
    if (!_speechReady || _listening) return;

    _listening = true;
    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
        localeId: 'es_ES',
      ),
    );
  }

  Future<void> stopListening() async {
    _listening = false;
    try {
      await _speech.stop();
    } catch (_) {}
  }

  Future<void> speak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _speaking) return;
    _speaking = true;
    try {
      if (await _speakViaRender(clean)) return;
      await _tts.stop();
      await _tts.speak(clean);
    } finally {
      _speaking = false;
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _player.stop();
    } catch (_) {}
    await _tts.stop();
    _speaking = false;
  }

  Future<bool> _speakViaRender(String text) async {
    try {
      final uri = Uri.parse('${AiConfig.httpBase}/tts');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'audio/mpeg',
            },
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Render TTS ${response.statusCode}: ${response.body}');
        return false;
      }
      return _playMp3Bytes(response.bodyBytes);
    } catch (e) {
      debugPrint('Render TTS: $e');
      return false;
    }
  }

  Future<bool> _playMp3Bytes(List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/conecta_tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await file.writeAsBytes(bytes, flush: true);
    await _player.stop();
    await _player.play(DeviceFileSource(file.path));
    await _player.onPlayerComplete.first.timeout(
      const Duration(seconds: 30),
      onTimeout: () {},
    );
    try {
      await file.delete();
    } catch (_) {}
    return true;
  }

  Future<void> dispose() async {
    await stopListening();
    await stopSpeaking();
    await _player.dispose();
  }
}
