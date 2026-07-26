import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:conecta_lsb/services/ai_config.dart';

class HelpAgentReply {
  final String sessionId;
  final String reply;
  final String source;
  final bool zavuConfigured;
  final String whatsappNumber;

  const HelpAgentReply({
    required this.sessionId,
    required this.reply,
    required this.source,
    this.zavuConfigured = false,
    this.whatsappNumber = '',
  });
}

class ZavuStatus {
  final bool configured;
  final String whatsappNumber;
  final String waMe;

  const ZavuStatus({
    required this.configured,
    this.whatsappNumber = '',
    this.waMe = '',
  });
}

/// Agente de ayuda Conecta: chat in-app vía Render + puente Zavu/WhatsApp.
class HelpAgentService {
  static final HelpAgentService instance = HelpAgentService._();
  HelpAgentService._();

  String? _sessionId;

  String? get sessionId => _sessionId;

  Future<HelpAgentReply> ask(String message) async {
    final uri = Uri.parse('${AiConfig.httpBase}/agent/help');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': message.trim(),
            if (_sessionId != null) 'sessionId': _sessionId,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Ayuda ${res.statusCode}: ${res.body}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    _sessionId = (map['sessionId'] ?? _sessionId)?.toString();
    final zavu = map['zavu'];
    final zMap = zavu is Map ? zavu as Map<String, dynamic> : const {};
    return HelpAgentReply(
      sessionId: _sessionId ?? '',
      reply: (map['reply'] ?? '').toString(),
      source: (map['source'] ?? 'local').toString(),
      zavuConfigured: zMap['configured'] == true,
      whatsappNumber: (zMap['whatsappNumber'] ?? '').toString(),
    );
  }

  Future<ZavuStatus> zavuStatus() async {
    final uri = Uri.parse('${AiConfig.httpBase}/agent/zavu/status');
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return const ZavuStatus(configured: false);
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return ZavuStatus(
      configured: map['configured'] == true,
      whatsappNumber: (map['whatsappNumber'] ?? '').toString(),
      waMe: (map['waMe'] ?? '').toString(),
    );
  }

  /// Envía texto por Zavu (WhatsApp/SMS) al número del usuario.
  Future<bool> sendViaZavu({required String to, required String text}) async {
    final uri = Uri.parse('${AiConfig.httpBase}/agent/zavu/send');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'to': to, 'text': text}),
        )
        .timeout(const Duration(seconds: 25));
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  void resetSession() => _sessionId = null;
}
