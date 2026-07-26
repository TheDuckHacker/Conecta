/// Configuración IA / voz.
/// Las claves viven en Render (GEMINI_API_KEY, ELEVENLABS_API_KEY).
/// La app llama al servidor: /ai/compose y /tts
class AiConfig {
  static const String realtimeHttpBase = String.fromEnvironment(
    'CONECTA_REALTIME_URL',
    defaultValue: 'https://conecta-realtime.onrender.com',
  );

  static const String elevenLabsFromEnv = String.fromEnvironment(
    'ELEVENLABS_API_KEY',
    defaultValue: '',
  );

  static const String geminiFromEnv = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static const String elevenLabsVoiceId = String.fromEnvironment(
    'ELEVENLABS_VOICE_ID',
    defaultValue: 'EXAVITQu4vr4xnSDxMaL',
  );

  static String? _elevenRuntime;
  static String? _geminiRuntime;

  static String get httpBase =>
      realtimeHttpBase.trim().replaceAll(RegExp(r'/$'), '');

  static String get elevenLabsApiKey =>
      (_elevenRuntime?.trim().isNotEmpty == true)
          ? _elevenRuntime!.trim()
          : elevenLabsFromEnv.trim();

  static String get geminiApiKey =>
      (_geminiRuntime?.trim().isNotEmpty == true)
          ? _geminiRuntime!.trim()
          : geminiFromEnv.trim();

  /// Siempre preferimos el servidor Render (claves allá).
  static bool get useRenderAi => true;
  static bool get hasElevenLabs => true; // vía Render /tts
  static bool get hasGemini => true; // vía Render /ai/compose

  // Compat
  static bool get hasOpenAi => hasGemini;
  static String get openAiApiKey => geminiApiKey;

  static void setElevenLabsKey(String? key) => _elevenRuntime = key;
  static void setGeminiKey(String? key) => _geminiRuntime = key;
  static void setOpenAiKey(String? key) => _geminiRuntime = key;
}
