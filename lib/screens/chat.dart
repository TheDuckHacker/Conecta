import 'dart:io';

import 'package:flutter/material.dart';
import 'package:conecta_lsb/screens/academy_tab.dart';
import 'package:conecta_lsb/screens/chats_tab.dart';
import 'package:conecta_lsb/screens/help_agent_screen.dart';
import 'package:conecta_lsb/screens/home_tab.dart';
import 'package:conecta_lsb/screens/profile.dart';
import 'package:conecta_lsb/screens/settings_tab.dart';
import 'package:conecta_lsb/screens/translation_tab.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/services/avatar_service.dart';
import 'package:conecta_lsb/services/call_invite_service.dart';
import 'package:conecta_lsb/services/notification_service.dart';
import 'package:conecta_lsb/theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  int _currentIndex = 0;
  final Map<int, Widget> _pageCache = {};
  String _avatarUrl = '';
  String _localAvatar = '';
  IncomingCall? _pendingCall;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
    _listenCallsForBell();
  }

  Future<void> _loadAvatar() async {
    try {
      final user = await AuthService().getCurrentUser();
      if (user == null) return;
      final profile = await AuthService().getUserProfile(user.$id);
      final local = await AvatarService().localPathFor(user.$id);
      if (!mounted) return;
      setState(() {
        _avatarUrl = profile?['avatar']?.toString() ?? '';
        _localAvatar = local ?? '';
      });
    } catch (_) {}
  }

  void _listenCallsForBell() {
    CallInviteService.instance.incoming.listen((call) {
      if (!mounted) return;
      setState(() => _pendingCall = call);
    });
  }

  Widget _pageFor(int index) {
    return _pageCache.putIfAbsent(index, () {
      switch (index) {
        case 0:
          return HomeTab(
            onStartCamera: () => setState(() => _currentIndex = 2),
          );
        case 1:
          return const ChatsTab();
        case 2:
          return const TranslationTab();
        case 3:
          return const AcademyTab();
        case 4:
        default:
          return const SettingsTab();
      }
    });
  }

  ImageProvider? get _headerAvatar {
    if (AvatarService.isNetworkAvatar(_avatarUrl)) {
      return NetworkImage(_avatarUrl);
    }
    if (_localAvatar.isNotEmpty && File(_localAvatar).existsSync()) {
      return FileImage(File(_localAvatar));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final img = _headerAvatar;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Row(
          children: [
            Semantics(
              button: true,
              label: 'Mi perfil',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ).then((_) {
                    _loadAvatar();
                    _pageCache.remove(4);
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white24,
                    backgroundImage: img,
                    onBackgroundImageError: img != null ? (_, __) {} : null,
                    child: img == null
                        ? const Icon(Icons.person,
                            color: Colors.white, size: 18)
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text('Conecta'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Asistente',
            icon: const Icon(
              Icons.smart_toy_outlined,
              color: Colors.white,
              size: 26,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpAgentScreen()),
              );
            },
          ),
          IconButton(
            tooltip:
                _pendingCall != null ? 'Llamada entrante' : 'Notificaciones',
            icon: Badge(
              isLabelVisible: _pendingCall != null,
              child: const Icon(
                Icons.notifications_none_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            onPressed: () async {
              final call = _pendingCall;
              if (call != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Llamada de ${call.fromName} — acepta en la pantalla',
                    ),
                    action: SnackBarAction(
                      label: 'Entendido',
                      textColor: AppColors.brandBright,
                      onPressed: () {},
                    ),
                  ),
                );
                return;
              }
              await NotificationService.instance.showSimple(
                title: 'Conecta',
                body: 'No tienes notificaciones nuevas',
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No tienes notificaciones nuevas'),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _pageFor(_currentIndex),
      bottomNavigationBar: _buildNavigationBar(),
    );
  }

  /// Barra con ícono + texto siempre visible: ningún botón solo con ícono
  /// (docs/flutter-design.md §8). Traducir va al centro por ser la acción
  /// principal de la app.
  Widget _buildNavigationBar() {
    return NavigationBar(
      selectedIndex: _currentIndex,
      onDestinationSelected: (index) {
        setState(() => _currentIndex = index);
        if (index == 4) _loadAvatar();
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Inicio',
        ),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline_rounded),
          selectedIcon: Icon(Icons.chat_bubble_rounded),
          label: 'Chats',
        ),
        NavigationDestination(
          icon: Icon(Icons.sign_language_outlined),
          selectedIcon: Icon(Icons.sign_language_rounded),
          label: 'Traducir',
        ),
        NavigationDestination(
          icon: Icon(Icons.school_outlined),
          selectedIcon: Icon(Icons.school_rounded),
          label: 'Academia',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'Ajustes',
        ),
      ],
    );
  }
}
