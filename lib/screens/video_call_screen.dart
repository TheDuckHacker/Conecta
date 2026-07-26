import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:conecta_lsb/services/call_service.dart';
import 'package:conecta_lsb/services/sign_detection_service.dart';
import 'package:conecta_lsb/services/voice_bridge_service.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

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
  final CallUserRole initialRole;

  const VideoCallScreen({
    super.key,
    required this.userName,
    required this.userAvatar,
    this.isVideoCall = true,
    this.currentUserId,
    this.otherUserId,
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
  String _statusHint = 'Iniciando cámara...';
  bool _handsVisible = false;

  String _roomId = '';
  StreamSubscription? _captionListen;
  StreamSubscription? _peerListen;
  bool _wsConnected = false;
  Timer? _timer;
  int _seconds = 0;

  static const _quickPhrases = [
    'Hola',
    '¿Cómo estás?',
    'Bien',
    'Gracias',
    'Por favor',
    'Sí',
    'No',
    'No entiendo',
    'Repite por favor',
    'Adiós',
  ];

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
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await previous?.dispose();
    await _camera!.initialize();
    if (!mounted) return;

    await _camera!.startImageStream(_onFrame);
    setState(() {
      _ready = true;
      _statusHint = _role == CallUserRole.deaf
          ? 'Haz señas frente a la cámara'
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

  InputImageRotation _rotation() {
    final sensor = _camera?.description.sensorOrientation ?? 0;
    return InputImageRotationValue.fromRawValue(sensor) ??
        InputImageRotation.rotation0deg;
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || _isVideoOff || _role != CallUserRole.deaf) return;
    _processing = true;
    try {
      final result = await _sign.processCameraImage(
        image,
        rotation: _rotation(),
      );
      if (result == null || !mounted) return;

      if (result.handsVisible != _handsVisible) {
        setState(() => _handsVisible = result.handsVisible);
      }

      if (result.phrase.isNotEmpty) {
        await _emitLocalCaption(result.phrase, role: 'sign', speak: true);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _initRoom() async {
    final me = widget.currentUserId;
    final other = widget.otherUserId;
    if (me == null || other == null || me.isEmpty || other.isEmpty) {
      // Sala local de prueba (un solo dispositivo / sin otro usuario)
      _roomId = 'solo-$me';
      return;
    }

    try {
      final room = await _calls.createOrJoinRoom(
        currentUserId: me,
        otherUserId: other,
      );
      _roomId = room.$id;

      await _calls.connect(
        roomId: _roomId,
        userId: me,
        role: _role == CallUserRole.deaf ? 'deaf' : 'hearing',
      );
      if (mounted) setState(() => _wsConnected = true);

      _captionListen = _calls.captions.listen((msg) {
        final sender = msg['userId']?.toString() ?? '';
        if (sender == me) return;
        final caption = (msg['text'] ?? '').toString().trim();
        if (caption.isEmpty || !mounted) return;
        setState(() {
          _remoteCaption = caption;
          _statusHint = 'En vivo (Render)';
        });
        if (_role == CallUserRole.hearing) {
          _voice.speak(caption);
        }
      });

      _peerListen = _calls.peers.listen((msg) {
        if (!mounted) return;
        final type = msg['type']?.toString();
        if (type == 'peer_joined') {
          setState(() => _statusHint = 'Conectado con el otro usuario');
        } else if (type == 'peer_left') {
          setState(() => _statusHint = 'El otro usuario salió');
        } else if (type == 'joined') {
          final peers = msg['peers'];
          final n = peers is List ? peers.length : 0;
          setState(() {
            _statusHint = n > 0
                ? 'Sala lista · $n en llamada'
                : 'Esperando al otro usuario...';
          });
        }
      });
    } catch (e) {
      debugPrint('initRoom: $e');
      if (mounted) {
        setState(() => _statusHint = 'Sin Render aún — reintentando...');
      }
    }
  }

  Future<void> _emitLocalCaption(
    String text, {
    required String role,
    bool speak = false,
  }) async {
    if (!mounted) return;
    setState(() => _localCaption = text);

    final me = widget.currentUserId;
    if (me != null && _roomId.isNotEmpty) {
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
        setState(() => _localCaption = text);
        if (isFinal) {
          await _emitLocalCaption(text, role: 'speech', speak: false);
        }
      },
    );
    if (mounted) {
      setState(() => _statusHint = 'Escuchando tu voz...');
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
    _captionListen?.cancel();
    _peerListen?.cancel();
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
            CameraPreview(_camera!)
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
                        '${_fmt(_seconds)}${_wsConnected ? ' · En vivo' : ''}',
                        style: const TextStyle(
                          color: Color(0xff37C8F2),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
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

          // Subtítulos
          Positioned(
            left: 16,
            right: 16,
            bottom: 150,
            child: Column(
              children: [
                if (_remoteCaption.isNotEmpty)
                  _captionBubble(
                    label: 'Ellos',
                    text: _remoteCaption,
                    color: const Color(0xff37C8F2),
                  ),
                if (_localCaption.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _captionBubble(
                    label: 'Tú',
                    text: _localCaption,
                    color: Colors.white,
                  ),
                ],
              ],
            ),
          ),

          // Frases rápidas (modo sordo)
          if (_role == CallUserRole.deaf)
            Positioned(
              left: 0,
              right: 0,
              bottom: 100,
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _quickPhrases.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final p = _quickPhrases[i];
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

  Widget _captionBubble({
    required String label,
    required String text,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ),
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
