import 'package:flutter/material.dart';
import 'package:conecta_lsb/screens/login.dart';
import 'package:conecta_lsb/screens/chat.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/services/call_invite_service.dart';
import 'package:conecta_lsb/services/notification_service.dart';
import 'package:conecta_lsb/services/settings_service.dart';
import 'package:conecta_lsb/widgets/incoming_call_host.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    debugPrint('Stack: ${details.stack}');
  };

  // Un error de construcción puntual (p. ej. una textura de video que se
  // liberó) no debe tapar la pantalla con el recuadro rojo de Flutter.
  ErrorWidget.builder = (details) {
    debugPrint('ErrorWidget: ${details.exceptionAsString()}');
    debugPrint('Stack: ${details.stack}');
    return const _SafeErrorTile();
  };

  await SettingsService.instance.load();
  await NotificationService.instance.init();

  runApp(const ConectaApp());
}

class _SafeErrorTile extends StatelessWidget {
  const _SafeErrorTile();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xff0F172A),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Reconectando…',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ),
    );
  }
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
        // force: limpia estados atascados (ringing/in_call de una llamada previa)
        _authService.setOnlineStatus(user.$id, true, force: true);
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
        // Refrescar llamada entrante ANTES de marcar online (por si hay ringing)
        await CallInviteService.instance.refreshIncoming();
        await _authService.setOnlineStatus(userId, true);
        _markedOnline = true;
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        // setOnlineStatus ya no pisa ringing/in_call
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
