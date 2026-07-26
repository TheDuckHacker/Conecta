import 'dart:async';

import 'package:flutter/material.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/services/call_invite_service.dart';
import 'package:conecta_lsb/services/call_ringtone_service.dart';
import 'package:conecta_lsb/services/notification_service.dart';
import 'package:conecta_lsb/screens/video_call_screen.dart';

/// Escucha llamadas entrantes: overlay + notificación del sistema.
class IncomingCallHost extends StatefulWidget {
  final Widget child;

  const IncomingCallHost({super.key, required this.child});

  @override
  State<IncomingCallHost> createState() => _IncomingCallHostState();
}

class _IncomingCallHostState extends State<IncomingCallHost>
    with WidgetsBindingObserver {
  final _auth = AuthService();
  final _invites = CallInviteService.instance;
  final _notifications = NotificationService.instance;
  final _ringtone = CallRingtoneService.instance;
  StreamSubscription? _sub;
  Timer? _watchdog;
  IncomingCall? _call;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    try {
      await _notifications.init();
      await _ringtone.init();
      _notifications.onTap = (payload) {
        // Al tocar la notificación, el overlay ya debería mostrarse
        debugPrint('Notificación tocada: $payload');
      };

      // Sin usuario no hay escucha de llamadas: reintentar si la red falla
      var user = await _auth.getCurrentUser();
      var tries = 0;
      while (user == null && mounted && tries < 5) {
        tries++;
        await Future.delayed(Duration(seconds: 2 * tries));
        user = await _auth.getCurrentUser();
      }
      if (user == null || !mounted) {
        debugPrint('IncomingCallHost: sin usuario, no se escuchan llamadas');
        return;
      }

      await _invites.startListening(
        userId: user.$id,
        userName: user.name.isNotEmpty ? user.name : 'Usuario',
      );

      // Vigilar que el lobby siga conectado (Render se duerme / cambia de red)
      _watchdog = Timer.periodic(const Duration(seconds: 15), (_) {
        unawaited(_invites.refreshIncoming());
      });

      _sub = _invites.incoming.listen((call) async {
        if (!mounted) return;
        setState(() => _call = call);
        if (call != null) {
          await _ringtone.start();
          await _notifications.showIncomingCall(
            callerName: call.fromName,
            payload: 'call:${call.roomId}:${call.fromUserId}',
          );
        } else {
          await _ringtone.stop();
          await _notifications.cancelIncomingCall();
        }
      });
    } catch (e) {
      debugPrint('IncomingCallHost: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver: no pisar ringing; refrescar llamada pendiente
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
    }
  }

  Future<void> _onResumed() async {
    await _invites.refreshIncoming();
    if (!mounted) return;
    if (_invites.current != null) {
      setState(() => _call = _invites.current);
      unawaited(_ringtone.start());
    }
  }

  Future<void> _accept() async {
    final call = _call;
    if (call == null || _starting) return;
    _starting = true;
    try {
      await _ringtone.stop();
      await _notifications.cancelIncomingCall();
      await _invites.acceptCall(call);
      if (!mounted) return;
      setState(() => _call = null);

      final me = await _auth.getCurrentUser();
      if (!mounted || me == null) {
        _starting = false;
        return;
      }

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            userName: call.fromName,
            userAvatar: '',
            isVideoCall: true,
            currentUserId: me.$id,
            otherUserId: call.fromUserId,
            roomId: call.roomId,
            isCaller: false,
            initialRole: CallUserRole.deaf,
          ),
        ),
      );
      await _invites.endCall(me.$id);
    } catch (e) {
      debugPrint('accept call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo contestar: $e')),
        );
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _reject() async {
    final call = _call;
    if (call == null) return;
    await _ringtone.stop();
    await _notifications.cancelIncomingCall();
    await _invites.rejectCall(call);
    if (mounted) setState(() => _call = null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchdog?.cancel();
    _sub?.cancel();
    unawaited(_ringtone.stop());
    _notifications.cancelIncomingCall();
    _invites.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_call != null) _buildIncomingOverlay(_call!),
      ],
    );
  }

  Widget _buildIncomingOverlay(IncomingCall call) {
    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: const Color(0xff0F172A),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xff37C8F2), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.videocam_rounded,
                  color: Color(0xff37C8F2),
                  size: 52,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Llamada entrante',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  call.fromName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Videollamada LSB · Acepta o rechaza',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _reject,
                        child: const Text('Rechazar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff2ECC71),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _accept,
                        child: const Text('Aceptar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
