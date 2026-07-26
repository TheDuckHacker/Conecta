import 'package:flutter/material.dart';
import 'package:conecta_lsb/screens/login.dart';
import 'package:conecta_lsb/screens/chat.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/services/notification_service.dart';
import 'package:conecta_lsb/services/settings_service.dart';
import 'package:conecta_lsb/widgets/incoming_call_host.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  await SettingsService.instance.load();
  await NotificationService.instance.init();

  runApp(const ConectaApp());
}

class ConectaApp extends StatelessWidget {
  const ConectaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Conecta LSB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xff37C8F2),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  final _authService = AuthService();
  bool _checking = true;
  bool _hasSession = false;
  bool _markedOnline = false;
  String? _userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      final user = await _authService.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _hasSession = user != null;
        _userId = user?.$id;
        _checking = false;
      });
      if (user != null && !_markedOnline) {
        _markedOnline = true;
        // No bloquear la UI esperando el status
        _authService.setOnlineStatus(user.$id, true);
      }
    } catch (e) {
      debugPrint('Auth check failed: $e');
      if (mounted) {
        setState(() {
          _hasSession = false;
          _checking = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    try {
      final userId = _userId;
      if (userId == null) return;

      if (state == AppLifecycleState.resumed) {
        await _authService.setOnlineStatus(userId, true);
        _markedOnline = true;
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        await _authService.setOnlineStatus(userId, false);
        _markedOnline = false;
      }
    } catch (e) {
      debugPrint('Lifecycle status error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xffE8F4F8),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xff37C8F2)),
              SizedBox(height: 16),
              Text(
                'Cargando...',
                style: TextStyle(
                  color: Color(0xff1A3A4A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasSession) {
      return const IncomingCallHost(child: ChatScreen());
    }

    return const Login();
  }
}
