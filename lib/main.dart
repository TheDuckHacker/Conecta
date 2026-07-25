import 'package:flutter/material.dart';
import 'package:conecta_lsb/screens/login.dart';
import 'package:conecta_lsb/screens/chat.dart';
import 'package:conecta_lsb/services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    final user = await _authService.getCurrentUser();
    if (user == null) return;

    if (state == AppLifecycleState.resumed) {
      await _authService.setOnlineStatus(user.$id, true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      await _authService.setOnlineStatus(user.$id, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _authService.getCurrentUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Color(0xff37C8F2))),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          _authService.setOnlineStatus(snapshot.data!.$id, true);
          return const ChatScreen();
        }

        return const Login();
      },
    );
  }
}
