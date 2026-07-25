import 'package:flutter/material.dart';
import 'package:conecta_lsb/screens/login.dart';
import 'package:conecta_lsb/screens/chat.dart';
import 'package:conecta_lsb/services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Evita que errores de red/realtime tumben la app
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

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
  late final Future _authFuture = _authService.getCurrentUser();
  bool _markedOnline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;

      // Solo paused/resumed: "inactive" se dispara al abrir teclado y NO debe marcar offline
      if (state == AppLifecycleState.resumed) {
        await _authService.setOnlineStatus(user.$id, true);
        _markedOnline = true;
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        await _authService.setOnlineStatus(user.$id, false);
        _markedOnline = false;
      }
    } catch (e) {
      debugPrint('Lifecycle status error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Color(0xff37C8F2))),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          if (!_markedOnline) {
            _markedOnline = true;
            // Fuera del build síncrono
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _authService.setOnlineStatus(snapshot.data!.$id, true);
            });
          }
          return const ChatScreen();
        }

        return const Login();
      },
    );
  }
}
