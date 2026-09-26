/// Configuración IA / voz.
/// Las claves viven SOLO en Render. La app nunca pide API keys al usuario.
/// - POST /ai/compose → Gemini en servidor (fallback local en app)
/// - POST /tts → ElevenLabs en servidor (fallback TTS del dispositivo)
class AiConfig {
  static const String realtimeHttpBase = String.fromEnvironment(
    'CONECTA_REALTIME_URL',
    defaultValue: 'https://conecta-realtime.onrender.com',
  );

  static const String elevenLabsVoiceId = String.fromEnvironment(
    'ELEVENLABS_VOICE_ID',
    defaultValue: 'EXAVITQu4vr4xnSDxMaL',
  );

  static const String _apiKey = String.fromEnvironment('CONECTA_API_KEY');

  static String get httpBase =>
      realtimeHttpBase.trim().replaceAll(RegExp(r'/$'), '');

  /// Headers estándar para requests HTTP al servidor realtime.
  /// Incluye X-Conecta-Key si está configurada (para producción).
  static Map<String, String> get headers {
    final map = <String, String>{'Content-Type': 'application/json'};
    if (_apiKey.isNotEmpty) {
      map['X-Conecta-Key'] = _apiKey;
    }
    return map;
  }

  /// Siempre vía Render; no hay claves en el teléfono.
  static bool get useRenderAi => true;
  static bool get hasElevenLabs => true;
  static bool get hasGemini => true;
}
