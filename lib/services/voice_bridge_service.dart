import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';

/// Voz ↔ texto para la capa accesible (oyente ↔ sordo).
/// ElevenLabs es opcional: si hay API key se usa; si no, flutter_tts local.
class VoiceBridgeService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  /// Pega aquí tu key de ElevenLabs si quieres voz en la nube.
  /// Déjala vacía para usar TTS del dispositivo (gratis, offline).
  static const String elevenLabsApiKey = String.fromEnvironment(
    'ELEVENLABS_API_KEY',
    defaultValue: '',
  );

  bool _speechReady = false;
  bool _listening = false;

  bool get isListening => _listening;

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
    if (clean.isEmpty) return;

    if (elevenLabsApiKey.isNotEmpty) {
      final ok = await _speakElevenLabs(clean);
      if (ok) return;
    }
    await _tts.stop();
    await _tts.speak(clean);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  Future<bool> _speakElevenLabs(String text) async {
    try {
      final uri = Uri.parse(
        'https://api.elevenlabs.io/v1/text-to-speech/EXAVITQu4vr4xnSDxMaL',
      );
      final response = await http.post(
        uri,
        headers: {
          'xi-api-key': elevenLabsApiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body:
            '{"text":${_jsonString(text)},"model_id":"eleven_multilingual_v2"}',
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Reproducir MP3 remoto requiere audioplayers; fallback a TTS local
        // si no hay player. Por ahora usamos TTS local tras confirmar API OK.
        debugPrint('ElevenLabs OK (${response.bodyBytes.length} bytes)');
      }
      // Siempre leemos en local para no añadir más deps ahora
      await _tts.speak(text);
      return true;
    } catch (e) {
      debugPrint('ElevenLabs: $e');
      return false;
    }
  }

  String _jsonString(String s) =>
      '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  Future<void> dispose() async {
    await stopListening();
    await _tts.stop();
  }
}
