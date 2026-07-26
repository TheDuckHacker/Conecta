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
        backgroundColor: const Color(0xff27C7D9),
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            GestureDetector(
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
                      ? const Icon(Icons.person, color: Colors.white, size: 18)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Conecta',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
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
                    backgroundColor: const Color(0xff27C7D9),
                    action: SnackBarAction(
                      label: 'OK',
                      textColor: Colors.white,
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
                    content: Text('No tienes nuevas notificaciones'),
                    backgroundColor: Color(0xff27C7D9),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xffE5F7FF),
              Color(0xffCDEFF7),
              Color(0xffA9E0F3),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _pageFor(_currentIndex),
      ),
      bottomNavigationBar: _buildCustomBottomNavigationBar(),
    );
  }

  Widget _buildCustomBottomNavigationBar() {
    return Container(
      height: 75,
      decoration: BoxDecoration(
        color: const Color(0xff27C7D9),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _nav(Icons.home_rounded, 0),
          _nav(Icons.chat_bubble_rounded, 1),
          GestureDetector(
            onTap: () => setState(() => _currentIndex = 2),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.videocam_rounded,
                color: Color(0xff27C7D9),
                size: 28,
              ),
            ),
          ),
          _nav(Icons.school_rounded, 3),
          _nav(Icons.settings_rounded, 4),
        ],
      ),
    );
  }

  Widget _nav(IconData icon, int index) {
    final selected = _currentIndex == index;
    return IconButton(
      icon: Icon(
        icon,
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.5),
        size: 26,
      ),
      onPressed: () {
        setState(() => _currentIndex = index);
        if (index == 4) _loadAvatar();
      },
    );
  }
}
