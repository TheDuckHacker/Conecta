import 'dart:io';

import 'package:flutter/material.dart';
import 'package:conecta_lsb/screens/login.dart';
import 'package:conecta_lsb/screens/profile.dart';
import 'package:conecta_lsb/screens/help_agent_screen.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/services/avatar_service.dart';
import 'package:conecta_lsb/services/call_invite_service.dart';
import 'package:conecta_lsb/services/settings_service.dart';
import 'package:conecta_lsb/services/voice_bridge_service.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _settings = SettingsService.instance;
  final _voice = VoiceBridgeService();
  String _userName = 'Usuario';
  String _userAvatar = '';
  String _localAvatar = '';
  String _userStatus = 'offline';
  String _userId = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _settings.load();
    await _voice.init();
    await _loadProfile();
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _loadProfile() async {
    try {
      final auth = AuthService();
      final user = await auth.getCurrentUser();
      if (user == null) return;
      _userId = user.$id;
      final profile = await auth.getUserProfile(user.$id);
      final local = await AvatarService().localPathFor(user.$id);
      if (!mounted) return;
      setState(() {
        _userName = profile?['name']?.toString() ?? user.name;
        _userAvatar = profile?['avatar']?.toString() ?? '';
        _userStatus = profile?['status']?.toString() ?? 'offline';
        _localAvatar = local ?? '';
      });
    } catch (e) {
      debugPrint('Settings load: $e');
    }
  }

  ImageProvider? _avatarImage() {
    if (AvatarService.isNetworkAvatar(_userAvatar)) {
      return NetworkImage(_userAvatar);
    }
    if (_localAvatar.isNotEmpty && File(_localAvatar).existsSync()) {
      return FileImage(File(_localAvatar));
    }
    return null;
  }

  Future<void> _pickVoiceRate() async {
    final rates = {
      'Lenta (0.8x)': 0.8,
      'Normal (1.0x)': 1.0,
      'Rápida (1.2x)': 1.2,
    };
    final chosen = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: rates.entries
              .map(
                (e) => ListTile(
                  title: Text(e.key),
                  trailing: _settings.voiceRate == e.value
                      ? const Icon(Icons.check, color: Color(0xff37C8F2))
                      : null,
                  onTap: () => Navigator.pop(ctx, e.value),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (chosen != null) {
      await _settings.setVoiceRate(chosen);
      setState(() {});
    }
  }

  Future<void> _logout() async {
    final auth = AuthService();
    try {
      await CallInviteService.instance.stopListening();
    } catch (_) {}
    if (_userId.isNotEmpty) {
      await auth.setOnlineStatus(_userId, false);
    }
    await auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Login()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xff37C8F2)),
      );
    }

    final online = AuthService.isOnlineStatus(_userStatus);
    final img = _avatarImage();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ).then((_) => _loadProfile());
            },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xffCDEFF7),
                  backgroundImage: img,
                  onBackgroundImageError: img != null ? (_, __) {} : null,
                  child: img == null
                      ? Text(
                          _userName.isNotEmpty
                              ? _userName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Color(0xff121B35),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff121B35),
                        ),
                      ),
                      Text(
                        online ? 'En línea' : 'Desconectado',
                        style: TextStyle(
                          color: online
                              ? const Color(0xff2ECC71)
                              : Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _header('MI CUENTA'),
          _item(
            icon: Icons.person_outline_rounded,
            title: 'Mi Perfil',
            subtitle: 'Nombre, foto y teléfono',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ).then((_) => _loadProfile());
            },
          ),
          _item(
            icon: Icons.smart_toy_rounded,
            title: 'Agente de ayuda (Zavu)',
            subtitle: 'Chat in-app y WhatsApp',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpAgentScreen()),
              );
            },
          ),
          const SizedBox(height: 16),
          _header('TRADUCCIÓN'),
          _item(
            icon: Icons.subtitles_rounded,
            title: 'Subtítulos automáticos',
            trailing: Switch(
              value: _settings.autoCaptions,
              activeThumbColor: const Color(0xff37C8F2),
              onChanged: (v) async {
                await _settings.setAutoCaptions(v);
                setState(() {});
              },
            ),
          ),
          _item(
            icon: Icons.record_voice_over_rounded,
            title: 'Voz de lectura',
            subtitle: _settings.voiceLabel,
            onTap: () async {
              await _settings.setVoiceLabel('TTS del dispositivo / servidor');
              setState(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_settings.voiceLabel)),
                );
              }
            },
          ),
          _item(
            icon: Icons.speed_rounded,
            title: 'Velocidad de reconocimiento',
            subtitle: '${_settings.voiceRate.toStringAsFixed(1)}x',
            onTap: _pickVoiceRate,
          ),
          const SizedBox(height: 16),
          _header('PREFERENCIAS'),
          _item(
            icon: Icons.dark_mode_rounded,
            title: 'Modo oscuro',
            subtitle: 'Se aplica al reiniciar sesión',
            trailing: Switch(
              value: _settings.darkMode,
              activeThumbColor: const Color(0xff37C8F2),
              onChanged: (v) async {
                await _settings.setDarkMode(v);
                setState(() {});
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        v
                            ? 'Modo oscuro activado (próximo reinicio)'
                            : 'Modo claro activado',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          _item(
            icon: Icons.language_rounded,
            title: 'Idioma de la interfaz',
            subtitle: 'Español',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('La interfaz está en español'),
                ),
              );
            },
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: const TextStyle(
            color: Color(0xffA8B8C0),
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _item({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xffE5F7FF),
        child: Icon(icon, color: const Color(0xff27C7D9)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
