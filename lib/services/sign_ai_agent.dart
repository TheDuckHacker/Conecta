import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_config.dart';

/// Resultado del agente: señas → frase en español.
class SignAgentResult {
  final List<String> signs;
  final String sentence;
  final String source; // local | gemini | cache
  final double confidence;

  const SignAgentResult({
    required this.signs,
    required this.sentence,
    required this.source,
    this.confidence = 0.5,
  });
}

/// Agente IA: Gemini en Render (+ fallback local enriquecido).
/// Debounce de llamadas remotas para no saturar /ai/compose.
class SignLanguageAiAgent {
  static final SignLanguageAiAgent instance = SignLanguageAiAgent._();
  SignLanguageAiAgent._();

  final List<String> _buffer = [];
  DateTime _lastSignAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSentence = '';
  String _lastSource = 'local';
  double _lastConfidence = 0.4;
  Timer? _remoteDebounce;
  int _composeGen = 0;
  Future<void>? _inflight;

  /// Notifica cuando Gemini refina la frase (UI debe escuchar).
  final ValueNotifier<SignAgentResult?> latest = ValueNotifier(null);

  /// Vocabulario conocido (LSB / MSL terms usados en la app).
  static const Set<String> knownVocab = {
    'Hola',
    'Sí',
    'No',
    'Bien',
    'Mal',
    'Yo',
    'Gracias',
    'Por favor',
    'Dolor',
    'Ayuda',
    'Doctor',
    'Hoy',
    'Mamá',
    'Papá',
    'Comer',
    'Beber',
    'Dormir',
    'Adiós',
    'Cómo',
    'Estás',
  };

  List<String> get buffer => List.unmodifiable(_buffer);
  String get lastSentence => _lastSentence;

  SignAgentResult get snapshot => SignAgentResult(
        signs: buffer,
        sentence: _lastSentence,
        source: _lastSource,
        confidence: _lastConfidence,
      );

  void clear() {
    _remoteDebounce?.cancel();
    _remoteDebounce = null;
    _composeGen++;
    _buffer.clear();
    _lastSentence = '';
    _lastSource = 'local';
    _lastConfidence = 0.4;
    latest.value = null;
  }

  Future<SignAgentResult> ingestSign(String rawSign) async {
    final sign = _normalize(rawSign);
    if (sign.isEmpty) return snapshot;

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
    _lastSource = 'local';
    _lastConfidence = _localConfidence(_buffer);

    final out = snapshot;
    latest.value = out;
    _scheduleRemoteCompose();
    return out;
  }

  /// Espera el refine remoto pendiente (útil al pausar / hablar).
  Future<SignAgentResult> flush() async {
    _remoteDebounce?.cancel();
    await _composeRemoteNow();
    await _inflight;
    return snapshot;
  }

  void _scheduleRemoteCompose() {
    _remoteDebounce?.cancel();
    final gen = ++_composeGen;
    _remoteDebounce = Timer(const Duration(milliseconds: 700), () {
      if (gen != _composeGen) return;
      _inflight = _composeRemoteNow();
    });
  }

  Future<void> _composeRemoteNow() async {
    if (_buffer.isEmpty) return;
    final snapshotSigns = List<String>.from(_buffer);
    final prev = _lastSentence;
    try {
      final remote = await _composeViaRender(snapshotSigns, previous: prev);
      if (remote == null) return;
      final sentence = remote['sentence'] as String?;
      if (sentence == null || sentence.trim().isEmpty) return;
      if (!_samePrefix(snapshotSigns, _buffer)) return;
      _lastSentence = sentence.trim();
      _lastSource = (remote['source'] as String?) ?? 'gemini';
      final c = remote['confidence'];
      _lastConfidence = c is num ? c.toDouble() : 0.85;
      latest.value = snapshot;
    } catch (e) {
      debugPrint('SignAgent Render/Gemini: $e');
    }
  }

  bool _samePrefix(List<String> a, List<String> b) {
    if (a.length > b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<Map<String, dynamic>?> _composeViaRender(
    List<String> signs, {
    String? previous,
  }) async {
    final uri = Uri.parse('${AiConfig.httpBase}/ai/compose');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'signs': signs,
            if (previous != null && previous.isNotEmpty) 'previous': previous,
            'locale': 'es-BO',
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('AI compose ${res.statusCode}: ${res.body}');
      return null;
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  double _localConfidence(List<String> signs) {
    if (signs.isEmpty) return 0;
    final known = signs.where(knownVocab.contains).length;
    return (0.35 + 0.5 * (known / signs.length)).clamp(0.2, 0.75);
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
      case 'por_favor':
        return 'Por favor';
      case 'dolor':
        return 'Dolor';
      case 'ayuda':
        return 'Ayuda';
      case 'doctor':
        return 'Doctor';
      case 'hoy':
        return 'Hoy';
      case 'mamá':
      case 'mama':
        return 'Mamá';
      case 'papá':
      case 'papa':
        return 'Papá';
      case 'cómo':
      case 'como':
        return 'Cómo';
      case 'estás':
      case 'estas':
        return 'Estás';
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
    if (signs.length == 1) {
      if (signs.first == 'Cómo') return '¿Cómo estás?';
      return signs.first;
    }

    final s = List<String>.from(signs);
    final set = s.toSet();

    // ¿Cómo estás?
    if (set.contains('Cómo') ||
        (set.contains('Cómo') && (set.contains('Estás') || set.contains('Bien'))) ||
        (set.contains('Hola') && set.contains('Cómo'))) {
      return '¿Cómo estás?';
    }
    if (set.contains('Hola') && set.contains('Bien') && s.length <= 3) {
      return 'Hola, ¿cómo estás?';
    }

    if (set.contains('Yo') && set.contains('Bien')) return 'Yo estoy bien';
    if (set.contains('Yo') && set.contains('Mal')) return 'Yo estoy mal';
    if (set.contains('Yo') && set.contains('Dolor')) return 'Yo tengo dolor';
    if (set.contains('Yo') && set.contains('Ayuda')) return 'Yo necesito ayuda';
    if (set.contains('Dolor') && set.contains('Doctor')) {
      return 'Tengo dolor, necesito un doctor';
    }
    if (set.contains('Ayuda') && set.contains('Doctor')) {
      return 'Necesito ayuda del doctor';
    }
    if (set.contains('Gracias') && set.contains('Por favor')) {
      return 'Por favor, gracias';
    }
    if (s.first == 'Hola') {
      final rest = s.skip(1).where((e) => e != 'Hola').toList();
      if (rest.isEmpty) return 'Hola';
      if (rest.contains('Bien')) return 'Hola, estoy bien';
      if (rest.contains('Mal')) return 'Hola, estoy mal';
      return 'Hola, ${rest.join(' ').toLowerCase()}';
    }
    if (s.first == 'Adiós' || s.last == 'Adiós') return 'Adiós';
    if (set.contains('Mamá') || set.contains('Papá')) {
      final who = set.contains('Mamá') ? 'mamá' : 'papá';
      if (set.contains('Hoy')) return 'Hoy veo a mi $who';
      return 'Es mi $who';
    }
    if (set.contains('Comer') || set.contains('Beber') || set.contains('Dormir')) {
      final action = s.firstWhere(
        (e) => e == 'Comer' || e == 'Beber' || e == 'Dormir',
      );
      final verb = action.toLowerCase();
      if (set.contains('Yo')) return 'Yo quiero $verb';
      if (set.contains('Hoy')) return 'Hoy quiero $verb';
      return 'Quiero $verb';
    }
    if (set.contains('Hoy') && s.length >= 2) {
      final rest = s.where((e) => e != 'Hoy').join(' ').toLowerCase();
      return 'Hoy $rest';
    }
    return '${s.join(', ')}.';
  }
}
