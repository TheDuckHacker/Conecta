import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:conecta_lsb/services/sign_detection_service.dart';
import 'package:conecta_lsb/services/voice_bridge_service.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Pestaña de traducción: cámara ON + detección automática de señas LSB.
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
  String _detected = 'Activa la cámara y haz una seña';
  final List<String> _sentence = [];

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
        setState(() => _detected = 'Sin cámara');
        return;
      }
      final desc = _cameras.firstWhere(
        (c) =>
            c.lensDirection ==
            (_isFront ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => _cameras.first,
      );
      final previous = _camera;
      _camera = CameraController(
        desc,
        ResolutionPreset.medium,
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
          _detected = 'Buscando manos...';
        });
      }
    } catch (e) {
      debugPrint('TranslationTab camera: $e');
      if (mounted) setState(() => _detected = 'Error de cámara');
    }
  }

  Future<void> _flip() async {
    if (_cameras.length < 2) return;
    _isFront = !_isFront;
    setState(() => _ready = false);
    await _startCamera();
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || !_ready) return;
    _busy = true;
    try {
      final sensor = _camera?.description.sensorOrientation ?? 0;
      final rotation = InputImageRotationValue.fromRawValue(sensor) ??
          InputImageRotation.rotation0deg;
      final result = await _sign.processCameraImage(
        image,
        rotation: rotation,
      );
      if (result == null || !mounted) return;

      if (result.handsVisible != _handsVisible) {
        setState(() {
          _handsVisible = result.handsVisible;
          if (_handsVisible && _detected == 'Buscando manos...') {
            _detected = 'Mano detectada — haz la seña';
          }
        });
      }

      if (result.phrase.isNotEmpty) {
        setState(() {
          if (_sentence.isEmpty || _sentence.last != result.phrase) {
            _sentence.add(result.phrase);
            if (_sentence.length > 8) _sentence.removeAt(0);
          }
          _detected = _sentence.join(' ');
        });
        await _voice.speak(result.phrase);
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
                        color: Colors.red.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                              radius: 4, backgroundColor: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            _handsVisible ? 'LSB ACTIVO' : 'REC LSB',
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
                  Icon(Icons.translate_rounded,
                      color: Color(0xff27C7D9), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'TRADUCCIÓN DETECTADA',
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
                  fontSize: 20,
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
                      _detected = 'Buscando manos...';
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
