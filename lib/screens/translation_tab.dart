import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:conecta_lsb/services/sign_detection_service.dart';
import 'package:conecta_lsb/services/voice_bridge_service.dart';

/// Pestaña de traducción: cámara ON + detección LSB en tiempo real.
class TranslationTab extends StatefulWidget {
  const TranslationTab({super.key});

  @override
  State<TranslationTab> createState() => _TranslationTabState();
}

class _TranslationTabState extends State<TranslationTab> {
  final _sign = SignDetectionService();
  final _voice = VoiceBridgeService();

  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  bool _isFront = true;
  bool _ready = false;
  bool _busy = false;
  bool _denied = false;
  bool _handsVisible = false;
  bool _bodyVisible = false;
  String _liveStatus = 'Iniciando...';
  String _detected = 'Activa la cámara y haz una seña';
  final List<String> _sentence = [];
  DateTime _lastSpeak = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      setState(() {
        _denied = true;
        _detected = 'Permiso de cámara necesario';
        _liveStatus = 'Sin permiso';
      });
      return;
    }
    await _voice.init();
    await _sign.start();
    await _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _detected = 'Sin cámara';
          _liveStatus = 'Error';
        });
        return;
      }
      final desc = _cameras.firstWhere(
        (c) =>
            c.lensDirection ==
            (_isFront ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => _cameras.first,
      );
      final previous = _camera;
      // Low = más FPS = mejor tiempo real
      _camera = CameraController(
        desc,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await previous?.dispose();
      await _camera!.initialize();
      await _camera!.startImageStream(_onFrame);
      if (mounted) {
        setState(() {
          _ready = true;
          _detected = 'Buscando cuerpo y manos...';
          _liveStatus = 'EN VIVO';
        });
      }
    } catch (e) {
      debugPrint('TranslationTab camera: $e');
      if (mounted) {
        setState(() {
          _detected = 'Error de cámara';
          _liveStatus = 'Error';
        });
      }
    }
  }

  Future<void> _flip() async {
    if (_cameras.length < 2) return;
    _isFront = !_isFront;
    setState(() => _ready = false);
    await _startCamera();
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || !_ready || _camera == null) return;
    _busy = true;
    try {
      final result = await _sign.processCameraImage(
        image,
        camera: _camera!.description,
      );
      if (result == null || !mounted) return;

      final statusLabel = switch (result.status) {
        'manos' => 'Manos detectadas — haz la seña',
        'cuerpo' => 'Cuerpo OK — sube las manos',
        'seña' => 'Seña detectada',
        'error_formato' => 'Ajustando cámara...',
        _ => 'Buscando en tiempo real...',
      };

      var changed = false;
      if (result.handsVisible != _handsVisible ||
          result.bodyVisible != _bodyVisible ||
          _liveStatus != 'EN VIVO') {
        _handsVisible = result.handsVisible;
        _bodyVisible = result.bodyVisible;
        _liveStatus = 'EN VIVO';
        changed = true;
      }

      if (result.phrase.isEmpty) {
        // Actualizar hint en vivo aunque no haya frase aún
        if (_detected.startsWith('Buscando') ||
            _detected.startsWith('Cuerpo') ||
            _detected.startsWith('Manos') ||
            _detected.startsWith('Ajustando') ||
            _detected == 'Activa la cámara y haz una seña') {
          _detected = statusLabel;
          changed = true;
        }
        if (changed && mounted) setState(() {});
        return;
      }

      if (_sentence.isEmpty || _sentence.last != result.phrase) {
        _sentence.add(result.phrase);
        if (_sentence.length > 8) _sentence.removeAt(0);
      }
      _detected = _sentence.join(' ');
      if (mounted) setState(() {});

      // TTS sin bloquear el pipeline de frames
      final now = DateTime.now();
      if (now.difference(_lastSpeak) > const Duration(milliseconds: 1200)) {
        _lastSpeak = now;
        unawaited(_voice.speak(result.phrase));
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    _sign.stop();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_ready && _camera != null)
                    CameraPreview(_camera!)
                  else
                    Container(
                      color: const Color(0xff121B35),
                      child: Center(
                        child: _denied
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Ve a Ajustes y permite la cámara para detectar señas LSB.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70),
                                ),
                              )
                            : const CircularProgressIndicator(
                                color: Color(0xff27C7D9),
                              ),
                      ),
                    ),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _handsVisible
                            ? const Color(0xff2ECC71).withValues(alpha: 0.9)
                            : Colors.red.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                              radius: 4, backgroundColor: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            _handsVisible
                                ? 'LSB EN VIVO'
                                : (_bodyVisible ? 'DETECTANDO' : _liveStatus),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      onPressed: _flip,
                      icon: const Icon(Icons.flip_camera_ios_rounded,
                          color: Colors.white),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xff27C7D9)),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'SUBTÍTULOS EN TIEMPO REAL',
                            style: TextStyle(
                              color: Color(0xff27C7D9),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _detected,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.closed_caption_rounded,
                      color: Color(0xff27C7D9), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'TEXTO DETECTADO',
                    style: TextStyle(
                      color: Color(0xffA8B8C0),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _detected,
                style: const TextStyle(
                  color: Color(0xff121B35),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (_detected.isEmpty) return;
                        _voice.speak(_detected);
                      },
                      icon: const Icon(Icons.volume_up_rounded),
                      label: const Text('Escuchar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff27C7D9),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _sentence.clear();
                      _detected = 'Buscando cuerpo y manos...';
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xff27C7D9),
                      side: const BorderSide(color: Color(0xff27C7D9)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Limpiar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
