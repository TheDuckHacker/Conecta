import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_config.dart';

/// Resultado del agente: señas → frase en español.
class SignAgentResult {
  final List<String> signs;
  final String sentence;
  final String source; // local | gemini | render

  const SignAgentResult({
    required this.signs,
    required this.sentence,
    required this.source,
  });
}

/// Agente IA: Gemini en Render (+ fallback local).
class SignLanguageAiAgent {
  static final SignLanguageAiAgent instance = SignLanguageAiAgent._();
  SignLanguageAiAgent._();

  final List<String> _buffer = [];
  DateTime _lastSignAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSentence = '';

  List<String> get buffer => List.unmodifiable(_buffer);
  String get lastSentence => _lastSentence;

  void clear() {
    _buffer.clear();
    _lastSentence = '';
  }

  Future<SignAgentResult> ingestSign(String rawSign) async {
    final sign = _normalize(rawSign);
    if (sign.isEmpty) {
      return SignAgentResult(
        signs: buffer,
        sentence: _lastSentence,
        source: 'local',
      );
    }

    final now = DateTime.now();
    if (now.difference(_lastSignAt) > const Duration(seconds: 4) &&
        _buffer.isNotEmpty) {
      _buffer.clear();
    }
    _lastSignAt = now;

    if (_buffer.isEmpty || _buffer.last != sign) {
      _buffer.add(sign);
      if (_buffer.length > 10) _buffer.removeAt(0);
    }

    final local = _composeLocal(_buffer);
    _lastSentence = local;

    // Pedir a Gemini (Render) desde 1 seña; mejora con 2+
    try {
      final remote = await _composeViaRender(_buffer);
      if (remote != null && remote.trim().isNotEmpty) {
        _lastSentence = remote.trim();
        return SignAgentResult(
          signs: buffer,
          sentence: _lastSentence,
          source: 'gemini',
        );
      }
    } catch (e) {
      debugPrint('SignAgent Render/Gemini: $e');
    }

    return SignAgentResult(
      signs: buffer,
      sentence: _lastSentence,
      source: 'local',
    );
  }

  Future<String?> _composeViaRender(List<String> signs) async {
    final uri = Uri.parse('${AiConfig.httpBase}/ai/compose');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'signs': signs}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('AI compose ${res.statusCode}: ${res.body}');
      return null;
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return (map['sentence'] ?? '').toString();
  }

  String _normalize(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    switch (t.toLowerCase()) {
      case 'hola':
        return 'Hola';
      case 'sí':
      case 'si':
        return 'Sí';
      case 'no':
        return 'No';
      case 'bien':
        return 'Bien';
      case 'mal':
        return 'Mal';
      case 'yo':
        return 'Yo';
      case 'gracias':
        return 'Gracias';
      case 'por favor':
        return 'Por favor';
      case 'dolor':
        return 'Dolor';
      case 'adiós':
      case 'adios':
        return 'Adiós';
      case 'comer':
        return 'Comer';
      case 'beber':
        return 'Beber';
      case 'dormir':
        return 'Dormir';
      default:
        return t[0].toUpperCase() + t.substring(1);
    }
  }

  String _composeLocal(List<String> signs) {
    if (signs.isEmpty) return '';
    if (signs.length == 1) return signs.first;
    final s = List<String>.from(signs);
    if (s.contains('Yo') && s.contains('Bien')) return 'Yo estoy bien';
    if (s.contains('Yo') && s.contains('Mal')) return 'Yo estoy mal';
    if (s.contains('Yo') && s.contains('Dolor')) return 'Yo tengo dolor';
    if (s.first == 'Hola' && s.length >= 2) {
      return 'Hola, ${s.skip(1).join(', ')}';
    }
    if (s.contains('Comer') || s.contains('Beber') || s.contains('Dormir')) {
      final action = s.firstWhere(
        (e) => e == 'Comer' || e == 'Beber' || e == 'Dormir',
      );
      if (s.contains('Yo')) return 'Yo quiero ${action.toLowerCase()}';
      return 'Quiero ${action.toLowerCase()}';
    }
    return '${s.join(', ')}.';
  }
}
