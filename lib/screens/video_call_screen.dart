import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:conecta_lsb/services/call_service.dart';
import 'package:conecta_lsb/services/call_invite_service.dart';
import 'package:conecta_lsb/services/help_agent_service.dart';
import 'package:conecta_lsb/services/sign_ai_agent.dart';
import 'package:conecta_lsb/services/sign_detection_service.dart';
import 'package:conecta_lsb/services/sign_guide.dart';
import 'package:conecta_lsb/services/voice_bridge_service.dart';
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
  List<CameraDescription> _cameras = [];
  bool _isFront = true;
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _ready = false;
  bool _permissionDenied = false;
  bool _processing = false;

  CallUserRole _role = CallUserRole.deaf;
  String _localCaption = '';
  String _remoteCaption = '';
  String _displayCaption = ''; // subtítulo grande en pantalla
  String _statusHint = 'Iniciando cámara...';
  bool _handsVisible = false;
  Timer? _captionHoldTimer;

  String _roomId = '';
  StreamSubscription? _captionListen;
  StreamSubscription? _peerListen;
  StreamSubscription? _callEventListen;
  bool _wsConnected = false;
  bool _peerConnected = false;
  bool _callRejected = false;
  Timer? _timer;
  Timer? _ringTimeout;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _boot();
  }

  Future<void> _boot() async {
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
    await _initCamera();
    await _initRoom();

    if (_role == CallUserRole.hearing && mic.isGranted) {
      await _startHearingMode();
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _statusHint = 'No hay cámara disponible');
        return;
      }
      final cam = _cameras.firstWhere(
        (c) =>
            c.lensDirection ==
            (_isFront ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => _cameras.first,
      );
      await _openCamera(cam);
    } catch (e) {
      debugPrint('initCamera: $e');
      if (mounted) setState(() => _statusHint = 'Error al abrir cámara');
    }
  }

  Future<void> _openCamera(CameraDescription desc) async {
    final previous = _camera;
    _camera = CameraController(
      desc,
      ResolutionPreset.medium, // buena calidad sin aplastar + detección OK
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await previous?.dispose();
    await _camera!.initialize();
    if (!mounted) return;

    _sign.syncOrientation(_camera);
    await _camera!.startImageStream(_onFrame);
    setState(() {
      _ready = true;
      _statusHint = _role == CallUserRole.deaf
          ? 'Detección LSB en vivo — haz señas'
          : 'Habla: el otro leerá subtítulos';
    });
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    _isFront = !_isFront;
    final cam = _cameras.firstWhere(
      (c) =>
          c.lensDirection ==
          (_isFront ? CameraLensDirection.front : CameraLensDirection.back),
      orElse: () => _cameras.first,
    );
    setState(() => _ready = false);
    await _openCamera(cam);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || _isVideoOff || _role != CallUserRole.deaf) return;
    if (_camera == null) return;
    _processing = true;
    try {
      _sign.syncOrientation(_camera);
      final result = await _sign.processCameraImage(
        image,
        camera: _camera!.description,
      );
      if (result == null || !mounted) return;

      if (result.handsVisible != _handsVisible) {
        setState(() => _handsVisible = result.handsVisible);
      }

      // Feedback en vivo aunque no haya frase aún
      if (result.phrase.isEmpty) {
        if (result.status == 'manos' || result.status == 'cuerpo') {
          setState(() {
            _statusHint = result.status == 'manos'
                ? 'Manos OK — haz la seña'
                : 'Cuerpo OK — sube las manos';
          });
        }
        return;
      }

      // No await speak: no congelar frames — agente arma frase
      if (result.phrase.isNotEmpty) {
        final agent =
            await SignLanguageAiAgent.instance.ingestSign(result.phrase);
        if (!mounted) return;
        unawaited(
          _emitLocalCaption(agent.sentence, role: 'sign', speak: true),
        );
      }
    } finally {
      _processing = false;
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
        _ringTimeout = Timer(const Duration(seconds: 45), () {
          if (!mounted || _peerConnected) return;
          setState(() => _statusHint = 'Sin respuesta — sigue en sala');
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
          setState(() {
            _peerConnected = true;
            _statusHint = 'Conectado · subtítulos activos';
          });
        } else if (type == 'peer_left') {
          setState(() {
            _peerConnected = false;
            _statusHint = 'El otro usuario salió';
          });
        } else if (type == 'joined') {
          final peers = msg['peers'];
          final n = peers is List ? peers.length : 0;
          setState(() {
            _peerConnected = n > 0;
            _statusHint = n > 0
                ? 'Sala lista · subtítulos en pantalla'
                : (widget.isCaller
                    ? 'Llamando... esperando que conteste'
                    : 'En llamada · subtítulos listos');
          });
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
    _captionHoldTimer?.cancel();
    _captionListen?.cancel();
    _peerListen?.cancel();
    _callEventListen?.cancel();
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
          if (_ready && !_isVideoOff && _camera != null)
            CameraCoverPreview(controller: _camera!)
          else
            Container(
              color: const Color(0xff0F172A),
              child: Center(
                child: _permissionDenied
                    ? const Text(
                        'Activa el permiso de cámara\nen Ajustes',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      )
                    : const CircularProgressIndicator(color: Color(0xff37C8F2)),
              ),
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
            right: 16,
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
                        _handsVisible
                            ? Icons.front_hand_rounded
                            : Icons.search_rounded,
                        color: _handsVisible
                            ? const Color(0xff2ECC71)
                            : Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _statusHint,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
                  onTap: () => setState(() => _isVideoOff = !_isVideoOff),
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
                    Text(
                      SignGuide.liveHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
