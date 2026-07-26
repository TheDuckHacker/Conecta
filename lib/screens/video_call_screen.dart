import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:conecta_lsb/services/auth_service.dart';
import 'package:conecta_lsb/services/call_service.dart';
import 'package:conecta_lsb/services/call_invite_service.dart';
import 'package:conecta_lsb/services/help_agent_service.dart';
import 'package:conecta_lsb/services/sign_detection_service.dart';
import 'package:conecta_lsb/services/sign_guide.dart';
import 'package:conecta_lsb/services/voice_bridge_service.dart';
import 'package:conecta_lsb/services/webrtc_call_session.dart';
import 'package:conecta_lsb/widgets/camera_cover_preview.dart';

enum CallUserRole { deaf, hearing }

/// Videollamada accesible LSB:
/// - Cámara real
/// - Persona sorda: señas → texto (+ voz para el oyente)
/// - Persona oyente: voz → subtítulos para que el sordo lea
/// - Subtítulos sincronizados por Appwrite Realtime
class VideoCallScreen extends StatefulWidget {
  final String userName;
  final String userAvatar;
  final bool isVideoCall;
  final String? currentUserId;
  final String? otherUserId;
  final String? roomId;
  final bool isCaller;
  final CallUserRole initialRole;

  const VideoCallScreen({
    super.key,
    required this.userName,
    required this.userAvatar,
    this.isVideoCall = true,
    this.currentUserId,
    this.otherUserId,
    this.roomId,
    this.isCaller = true,
    this.initialRole = CallUserRole.deaf,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final _sign = SignDetectionService();
  final _voice = VoiceBridgeService();
  final _calls = CallService();

  CameraController? _camera;
  bool _isFront = true;
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _ready = false;
  bool _permissionDenied = false;

  CallUserRole _role = CallUserRole.deaf;
  String _localCaption = '';
  String _remoteCaption = '';
  String _displayCaption = '';
  String _statusHint = 'Iniciando cámara...';
  Timer? _captionHoldTimer;

  String _roomId = '';
  String _myName = 'Contacto';
  StreamSubscription? _captionListen;
  StreamSubscription? _peerListen;
  StreamSubscription? _callEventListen;
  bool _wsConnected = false;
  bool _peerConnected = false;
  bool _callRejected = false;
  Timer? _timer;
  Timer? _ringTimeout;
  Timer? _reRingTimer;
  int _seconds = 0;

  /// Pantalla grande = el otro; PiP = yo. Tocar PiP intercambia.
  bool _remoteIsMain = true;
  WebRtcCallSession? _webrtc;
  bool _webrtcReady = false;
  bool _remoteVideoReady = false;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _boot();
  }

  Future<void> _boot() async {
    try {
      final me = await AuthService().getCurrentUser();
      if (me != null && me.name.isNotEmpty) _myName = me.name;
    } catch (_) {}

    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted) {
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _statusHint = 'Permiso de cámara denegado';
        });
      }
      return;
    }

    await _voice.init();
    await _sign.start();
    await _initRoom();
    await _startWebRtc();

    if (_role == CallUserRole.hearing && mic.isGranted) {
      await _startHearingMode();
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  Future<void> _startWebRtc() async {
    final me = widget.currentUserId;
    if (me == null || me.isEmpty || _roomId.isEmpty || _roomId.startsWith('solo')) {
      return;
    }
    try {
      final session = WebRtcCallSession(
        calls: _calls,
        roomId: _roomId,
        localUserId: me,
        isCaller: widget.isCaller,
      );
      await session.start();
      session.remoteReady.addListener(_onRemoteVideoReady);
      _webrtc = session;
      if (!mounted) return;
      setState(() {
        _webrtcReady = true;
        _ready = true;
        _statusHint = widget.isCaller
            ? 'Video listo · llamando a ${widget.userName}…'
            : 'Video listo · conectando…';
      });
      // Si el otro ya estaba en la sala, negociar ya
      if (_peerConnected) {
        await session.onPeerJoined();
      }
    } catch (e) {
      debugPrint('WebRTC start: $e');
      if (mounted) {
        setState(() => _statusHint = 'Error de video: $e');
      }
    }
  }

  void _onRemoteVideoReady() {
    if (!mounted) return;
    final ready = _webrtc?.remoteReady.value ?? false;
    setState(() {
      _remoteVideoReady = ready;
      if (ready) {
        _statusHint = 'Videollamada en vivo';
      }
    });
  }

  Future<void> _flipCamera() async {
    _isFront = !_isFront;
    try {
      await _webrtc?.switchCamera();
    } catch (e) {
      debugPrint('flip webrtc: $e');
    }
  }

  void _showOnScreenCaption(String text, {bool fromRemote = false}) {
    final clean = text.trim();
    if (clean.isEmpty || !mounted) return;
    setState(() {
      if (fromRemote) {
        _remoteCaption = clean;
      } else {
        _localCaption = clean;
      }
      // Siempre pintar en el banner grande
      _displayCaption = clean;
    });
  }

  Future<void> _initRoom() async {
    final me = widget.currentUserId;
    final other = widget.otherUserId;
    if (me == null || me.isEmpty) {
      _roomId = 'solo-local';
      return;
    }

    try {
      if (widget.roomId != null && widget.roomId!.isNotEmpty) {
        _roomId = widget.roomId!;
      } else if (other != null && other.isNotEmpty) {
        final room = await _calls.createOrJoinRoom(
          currentUserId: me,
          otherUserId: other,
        );
        _roomId = room.$id;
      } else {
        _roomId = 'solo-$me';
      }

      await CallInviteService.instance.markInCall(me, _roomId);

      await _calls.connect(
        roomId: _roomId,
        userId: me,
        role: _role == CallUserRole.deaf ? 'deaf' : 'hearing',
      );
      if (mounted) {
        setState(() {
          _wsConnected = true;
          _statusHint = widget.isCaller
              ? 'Llamando a ${widget.userName}...'
              : 'Conectando subtítulos...';
        });
      }

      if (widget.isCaller) {
        _startReRinging(me, other);
        _ringTimeout = Timer(const Duration(seconds: 45), () {
          _reRingTimer?.cancel();
          if (!mounted || _peerConnected) return;
          setState(() => _statusHint =
              'Sin respuesta — el contacto debe tener Conecta abierta');
        });
      }

      _captionListen = _calls.captions.listen((msg) {
        final sender = msg['userId']?.toString() ?? '';
        if (sender == me) return;
        final caption = (msg['text'] ?? '').toString().trim();
        if (caption.isEmpty || !mounted) return;
        _showOnScreenCaption(caption, fromRemote: true);
        setState(() => _statusHint = 'Subtítulo en vivo');
        if (_role == CallUserRole.hearing) {
          unawaited(_voice.speak(caption));
        }
      });

      _peerListen = _calls.peers.listen((msg) {
        if (!mounted) return;
        final type = msg['type']?.toString();
        if (type == 'peer_joined') {
          _ringTimeout?.cancel();
          _reRingTimer?.cancel();
          setState(() {
            _peerConnected = true;
            _statusHint = _remoteVideoReady
                ? 'Videollamada en vivo'
                : 'Conectado · abriendo video…';
          });
          unawaited(_webrtc?.onPeerJoined());
        } else if (type == 'peer_left') {
          setState(() {
            _peerConnected = false;
            _remoteVideoReady = false;
            _statusHint = 'El otro usuario salió';
          });
        } else if (type == 'joined') {
          final peers = msg['peers'];
          final n = peers is List ? peers.length : 0;
          setState(() {
            _peerConnected = n > 0;
            _statusHint = n > 0
                ? 'Sala lista · abriendo video…'
                : (widget.isCaller
                    ? 'Llamando... esperando que conteste'
                    : 'En llamada · esperando video');
          });
          if (n > 0) {
            unawaited(_webrtc?.onPeerJoined());
          }
        }
      });

      _callEventListen = CallInviteService.instance.callEvents.listen((msg) {
        if (!mounted) return;
        if (msg['type']?.toString() == 'call_response' &&
            msg['accepted'] == false) {
          setState(() {
            _callRejected = true;
            _statusHint = 'Llamada rechazada';
          });
        }
      });
    } catch (e) {
      debugPrint('initRoom: $e');
      if (mounted) {
        setState(() => _statusHint = 'Reconectando servidor...');
      }
    }
  }

  /// Timbra cada 3 s hasta que el otro entre (o se agote el tiempo).
  void _startReRinging(String me, String? other) {
    if (other == null || other.isEmpty) return;
    _reRingTimer?.cancel();
    _reRingTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!mounted || _peerConnected || _callRejected) {
        t.cancel();
        return;
      }
      await CallInviteService.instance.reRing(
        callerId: me,
        callerName: _myName,
        calleeId: other,
        roomId: _roomId,
      );
    });
  }

  Future<void> _emitLocalCaption(
    String text, {
    required String role,
    bool speak = false,
  }) async {
    if (!mounted) return;
    _showOnScreenCaption(text, fromRemote: false);

    final me = widget.currentUserId ?? 'local';
    if (_roomId.isNotEmpty) {
      await _calls.sendCaption(
        roomId: _roomId,
        senderId: me,
        text: text,
        role: role,
      );
    }
    if (speak && _role == CallUserRole.deaf) {
      await _voice.speak(text);
    }
  }

  Future<void> _startHearingMode() async {
    await _voice.startListening(
      onResult: (text, isFinal) async {
        if (!mounted || text.trim().isEmpty) return;
        // Mostrar en pantalla en tiempo real (parciales también)
        _showOnScreenCaption(text, fromRemote: false);
        if (isFinal) {
          await _emitLocalCaption(text, role: 'speech', speak: false);
        }
      },
    );
    if (mounted) {
      setState(() => _statusHint = 'Habla: verás subtítulos aquí');
    }
  }

  Future<void> _setRole(CallUserRole role) async {
    if (role == _role) return;
    await _voice.stopListening();
    setState(() {
      _role = role;
      _statusHint = role == CallUserRole.deaf
          ? 'Haz señas frente a la cámara'
          : 'Habla: el otro leerá subtítulos';
    });
    if (role == CallUserRole.hearing) {
      final mic = await Permission.microphone.request();
      if (mic.isGranted) await _startHearingMode();
    }
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ringTimeout?.cancel();
    _reRingTimer?.cancel();
    _captionHoldTimer?.cancel();
    _captionListen?.cancel();
    _peerListen?.cancel();
    _callEventListen?.cancel();
    _webrtc?.remoteReady.removeListener(_onRemoteVideoReady);
    unawaited(_webrtc?.dispose());
    _webrtc = null;
    final me = widget.currentUserId;
    if (me != null) {
      unawaited(CallInviteService.instance.endCall(me));
      if (widget.isCaller && widget.otherUserId != null) {
        unawaited(
          CallInviteService.instance.clearRingingOnCallee(widget.otherUserId!),
        );
      }
    }
    _calls.dispose();
    _camera?.dispose();
    _sign.stop();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.userName.isNotEmpty ? widget.userName : 'Contacto';

    return Scaffold(
      backgroundColor: const Color(0xff0F172A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ——— Vista PRINCIPAL (grande) ———
          Positioned.fill(child: _buildMainSurface()),

          // ——— PiP pequeña (esquina) ———
          Positioned(
            top: MediaQuery.paddingOf(context).top + 72,
            right: 14,
            child: _buildPip(),
          ),

          // Gradiente inferior para leer subtítulos
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 280,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),

          // Header
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _callRejected
                            ? 'Rechazada'
                            : '${_fmt(_seconds)}${_wsConnected ? (_peerConnected ? ' · En llamada' : ' · Llamando...') : ''}',
                        style: TextStyle(
                          color: _callRejected
                              ? Colors.redAccent
                              : const Color(0xff37C8F2),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                _callHelpBtn(),
                const SizedBox(width: 8),
                _roleChip(),
              ],
            ),
          ),

          // Estado detección
          Positioned(
            top: 110,
            left: 16,
            right: 140,
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _remoteVideoReady
                            ? Icons.videocam_rounded
                            : Icons.hourglass_top_rounded,
                        color: _remoteVideoReady
                            ? const Color(0xff2ECC71)
                            : Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _statusHint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // SUBTÍTULOS GRANDES (siempre visibles en pantalla)
          Positioned(
            left: 12,
            right: 12,
            bottom: _role == CallUserRole.deaf ? 160 : 120,
            child: _buildLiveSubtitles(),
          ),

          // Frases rápidas (modo sordo)
          if (_role == CallUserRole.deaf)
            Positioned(
              left: 0,
              right: 0,
              bottom: 108,
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _sign.quickPhrases.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final p = _sign.quickPhrases[i];
                    return ActionChip(
                      label: Text(p),
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      labelStyle: const TextStyle(color: Colors.white),
                      onPressed: () =>
                          _emitLocalCaption(p, role: 'typed', speak: true),
                    );
                  },
                ),
              ),
            ),

          // Controles
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _btn(
                  icon: _isMuted ? Icons.mic_off : Icons.mic,
                  active: _isMuted,
                  onTap: () async {
                    setState(() => _isMuted = !_isMuted);
                    await _webrtc?.setMicEnabled(!_isMuted);
                    if (_isMuted) {
                      await _voice.stopListening();
                    } else if (_role == CallUserRole.hearing) {
                      await _startHearingMode();
                    }
                  },
                ),
                _btn(
                  icon: _isVideoOff ? Icons.videocam_off : Icons.videocam,
                  active: _isVideoOff,
                  onTap: () async {
                    setState(() => _isVideoOff = !_isVideoOff);
                    await _webrtc?.setCamEnabled(!_isVideoOff);
                  },
                ),
                _btn(
                  icon: Icons.cameraswitch_rounded,
                  onTap: _flipCamera,
                ),
                _btn(
                  icon: Icons.call_end_rounded,
                  color: Colors.redAccent,
                  size: 64,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainSurface() {
    if (_remoteIsMain) {
      return _buildRemoteView(full: true);
    }
    return _buildLocalView(full: true);
  }

  Widget _buildPip() {
    return GestureDetector(
      onTap: () => setState(() => _remoteIsMain = !_remoteIsMain),
      child: Container(
        width: 112,
        height: 168,
        decoration: BoxDecoration(
          color: const Color(0xff0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white70, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_remoteIsMain)
              _buildLocalView(full: false)
            else
              _buildRemoteView(full: false),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _remoteIsMain ? 'Tú' : widget.userName.split(' ').first,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.swap_horiz_rounded,
                  color: Colors.white70, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalView({required bool full}) {
    if (_permissionDenied) {
      return _placeholder(
        icon: Icons.videocam_off_rounded,
        label: 'Sin permiso de cámara',
      );
    }
    if (_isVideoOff) {
      return _placeholder(
        icon: Icons.videocam_off_rounded,
        label: 'Cámara apagada',
      );
    }
    final webrtc = _webrtc;
    if (_webrtcReady && webrtc != null) {
      return RTCVideoView(
        webrtc.localRenderer,
        mirror: _isFront,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    if (_ready && _camera != null) {
      return CameraCoverPreview(controller: _camera!);
    }
    return _placeholder(
      icon: Icons.person_rounded,
      label: 'Tu cámara…',
    );
  }

  Widget _buildRemoteView({required bool full}) {
    final webrtc = _webrtc;
    if (_remoteVideoReady && webrtc != null) {
      return RTCVideoView(
        webrtc.remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return _placeholder(
      icon: _peerConnected
          ? Icons.videocam_rounded
          : Icons.hourglass_top_rounded,
      label: _peerConnected
          ? 'Conectando video de ${widget.userName}…'
          : (widget.isCaller
              ? 'Llamando a ${widget.userName}…'
              : 'Conectando…'),
      avatarLetter: widget.userName.isNotEmpty
          ? widget.userName[0].toUpperCase()
          : '?',
    );
  }

  Widget _placeholder({
    required IconData icon,
    required String label,
    String? avatarLetter,
  }) {
    return ColoredBox(
      color: const Color(0xff0F172A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (avatarLetter != null)
                CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xff37C8F2),
                  child: Text(
                    avatarLetter,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Icon(icon, color: Colors.white38, size: 48),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _callHelpBtn() {
    return Material(
      color: const Color(0xff27C7D9),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _openCallHelp,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_rounded, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                'Ayuda',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCallHelp() async {
    final ctrl = TextEditingController();
    String answer = '';
    bool busy = false;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> ask([String? preset]) async {
              final q = (preset ?? ctrl.text).trim();
              if (q.isEmpty || busy) return;
              setModal(() => busy = true);
              try {
                final out = await HelpAgentService.instance.ask(
                  'Estoy en una videollamada LSB en la app Conecta. $q',
                );
                setModal(() {
                  answer = out.reply;
                  busy = false;
                });
              } catch (_) {
                setModal(() {
                  answer =
                      'Tips rápidos en llamada:\n'
                      '• Hola: mano bien arriba + vaivén\n'
                      '• Cómo estás: mano cerca de la cara\n'
                      '• Yo / Bien: pecho quieto\n'
                      '• Usa las chips de frases rápidas abajo.';
                  busy = false;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ayuda en la videollamada',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Imita las señas de la guía (mismas que Academia y Traducción).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        SignGuide.asset,
                        fit: BoxFit.contain,
                        height: 160,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      SignGuide.liveHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xff37C8F2),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        '¿Cómo hago Hola?',
                        '¿Cómo digo cómo estás?',
                        'No me detecta las manos',
                      ]
                          .map(
                            (s) => ActionChip(
                              label:
                                  Text(s, style: const TextStyle(fontSize: 12)),
                              onPressed: busy ? null : () => ask(s),
                              backgroundColor: Colors.white12,
                              labelStyle:
                                  const TextStyle(color: Colors.white),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Escribe tu duda…',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          onPressed: busy ? null : () => ask(),
                          icon: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xff37C8F2),
                                  ),
                                )
                              : const Icon(Icons.send_rounded,
                                  color: Color(0xff37C8F2)),
                        ),
                      ),
                      onSubmitted: (_) => ask(),
                    ),
                    if (answer.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xff37C8F2)),
                        ),
                        child: Text(
                          answer,
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    ctrl.dispose();
  }

  Widget _roleChip() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _roleBtn('Sordo', CallUserRole.deaf),
          _roleBtn('Oyente', CallUserRole.hearing),
        ],
      ),
    );
  }

  Widget _roleBtn(String label, CallUserRole role) {
    final selected = _role == role;
    return GestureDetector(
      onTap: () => _setRole(role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff37C8F2) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildLiveSubtitles() {
    final hasText = _displayCaption.trim().isNotEmpty;
    final placeholder = _role == CallUserRole.deaf
        ? 'Los subtítulos aparecerán aquí al hacer señas…'
        : 'Los subtítulos aparecerán aquí al hablar…';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Banda principal estilo TV / YouTube
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasText
                  ? const Color(0xff37C8F2)
                  : Colors.white24,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.closed_caption_rounded,
                    color: hasText
                        ? const Color(0xff37C8F2)
                        : Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    hasText ? 'SUBTÍTULOS' : 'ESPERANDO SUBTÍTULOS',
                    style: TextStyle(
                      color: hasText
                          ? const Color(0xff37C8F2)
                          : Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                hasText ? _displayCaption : placeholder,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: hasText ? Colors.white : Colors.white60,
                  fontSize: hasText ? 26 : 16,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  shadows: const [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_remoteCaption.isNotEmpty &&
            _localCaption.isNotEmpty &&
            _remoteCaption != _localCaption) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Tú: $_localCaption',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _btn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    Color? color,
    double size = 52,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? (active ? Colors.white : Colors.white24),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: color != null
              ? Colors.white
              : (active ? Colors.black : Colors.white),
          size: 24,
        ),
      ),
    );
  }
}
