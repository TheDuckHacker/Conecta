import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de la app (ajustes persistentes).
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _kAutoCaptions = 'pref_auto_captions';
  static const _kVoiceRate = 'pref_voice_rate';
  static const _kDarkMode = 'pref_dark_mode';
  static const _kVoiceLabel = 'pref_voice_label';
  static const _kAcademyProgress = 'pref_academy_progress';

  bool autoCaptions = true;
  double voiceRate = 1.0;
  bool darkMode = false;
  String voiceLabel = 'Voz del servidor / dispositivo';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    autoCaptions = p.getBool(_kAutoCaptions) ?? true;
    voiceRate = p.getDouble(_kVoiceRate) ?? 1.0;
    darkMode = p.getBool(_kDarkMode) ?? false;
    voiceLabel = p.getString(_kVoiceLabel) ?? voiceLabel;
  }

  Future<void> setAutoCaptions(bool v) async {
    autoCaptions = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoCaptions, v);
  }

  Future<void> setVoiceRate(double v) async {
    voiceRate = v;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kVoiceRate, v);
  }

  Future<void> setDarkMode(bool v) async {
    darkMode = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDarkMode, v);
  }

  Future<void> setVoiceLabel(String v) async {
    voiceLabel = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kVoiceLabel, v);
  }

  Future<Map<String, double>> loadAcademyProgress() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kAcademyProgress);
    if (raw == null || raw.isEmpty) return {};
    final map = <String, double>{};
    for (final part in raw.split('|')) {
      final kv = part.split('=');
      if (kv.length == 2) {
        map[kv[0]] = double.tryParse(kv[1]) ?? 0;
      }
    }
    return map;
  }

  Future<void> saveAcademyProgress(String courseId, double progress) async {
    final map = await loadAcademyProgress();
    map[courseId] = progress.clamp(0.0, 1.0);
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kAcademyProgress,
      map.entries.map((e) => '${e.key}=${e.value}').join('|'),
    );
  }
}
