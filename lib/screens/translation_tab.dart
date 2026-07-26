import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:conecta_lsb/services/sign_ai_agent.dart';
import 'package:conecta_lsb/services/sign_detection_service.dart';
import 'package:conecta_lsb/services/voice_bridge_service.dart';
import 'package:conecta_lsb/widgets/camera_cover_preview.dart';

/// Pestaña de traducción: cámara + señas → frase + voz.
class TranslationTab extends StatefulWidget {
  const TranslationTab({super.key});

  @override
  State<TranslationTab> createState() => _TranslationTabState();
}

class _TranslationTabState extends State<TranslationTab> {
  final _sign = SignDetectionService();
  final _voice = VoiceBridgeService();
  final _agent = SignLanguageAiAgent.instance;

  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  bool _isFront = true;
  bool _ready = false;
  bool _busy = false;
  bool _denied = false;
  bool _handsVisible = false;
  bool _bodyVisible = false;
  String _liveStatus = 'Iniciando...';
  String _hint = 'Haz señas: se armará la frase';
  String _signsLine = '';
  String _sentence = '';
  String _agentSource = 'local';
  DateTime _lastSpeak = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _agent.latest.addListener(_onAgentUpdate);
    _boot();
  }

  void _onAgentUpdate() {
    final out = _agent.latest.value;
    if (out == null || !mounted) return;
    setState(() {
      _signsLine = out.signs.join(' → ');
      _sentence = out.sentence;
      _agentSource = out.source;
    });
    if (out.source == 'gemini') {
      final now = DateTime.now();
      if (now.difference(_lastSpeak) > const Duration(milliseconds: 900)) {
        _lastSpeak = now;
        unawaited(_voice.speak(out.sentence));
      }
    }
  }

  Future<void> _boot() async {
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      setState(() {
        _denied = true;
        _hint = 'Permiso de cámara necesario';
        _liveStatus = 'Sin permiso';
      });
      return;
    }
    await _voice.init();
    await _sign.start();
    await _startCamera();
    if (mounted) {
      setState(() {
        _liveStatus = 'EN VIVO';
      });
    }
  }

  Future<void> _startCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _hint = 'Sin cámara';
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
      _sign.syncOrientation(_camera);
      await _camera!.startImageStream(_onFrame);
      if (mounted) {
        setState(() {
          _ready = true;
          _hint = 'Haz señas frente a la cámara';
          _liveStatus = 'EN VIVO';
        });
      }
    } catch (e) {
      debugPrint('TranslationTab camera: $e');
      if (mounted) {
        setState(() {
          _hint = 'Error de cámara';
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
      _sign.syncOrientation(_camera);
      final result = await _sign.processCameraImage(
        image,
        camera: _camera!.description,
      );
      if (result == null || !mounted) return;

      var changed = false;
      if (result.handsVisible != _handsVisible ||
          result.bodyVisible != _bodyVisible) {
        _handsVisible = result.handsVisible;
        _bodyVisible = result.bodyVisible;
        changed = true;
      }

      if (result.phrase.isEmpty) {
        if (_sentence.isEmpty) {
          final h = !_handsVisible
              ? 'Buscando manos… cuerpo visible, luz buena'
              : 'Manos OK — Hola=saludo alto | Cómo=cara | Yo=pecho | Bien=quieto';
          if (_hint != h) {
            _hint = h;
            changed = true;
          }
        }
        if (changed && mounted) setState(() {});
        return;
      }

      // Agente IA: arma palabras → frase en español
      final agentOut = await _agent.ingestSign(result.phrase);
      if (!mounted) return;

      setState(() {
        _signsLine = agentOut.signs.join(' → ');
        _sentence = agentOut.sentence;
        _agentSource = agentOut.source;
        _hint = result.phrase;
      });

      // Leer la frase armada (servidor o TTS local)
      final now = DateTime.now();
      if (now.difference(_lastSpeak) > const Duration(milliseconds: 1200)) {
        _lastSpeak = now;
        unawaited(_voice.speak(agentOut.sentence));
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _clear() async {
    _agent.clear();
    setState(() {
      _signsLine = '';
      _sentence = '';
      _hint = 'Haz señas frente a la cámara';
    });
  }

  void _showSignGuide() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Guía de señas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xff121B35),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Colócate a 1–2 metros, con buena luz y el pecho visible. '
              'Mantén cada seña 1–2 segundos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/msl/guia_senas.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),
            ..._guideItems.map(
              (g) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xffE3F7FB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(g.$3, color: const Color(0xff27C7D9)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.$1,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xff121B35),
                            ),
                          ),
                          Text(
                            g.$2,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const List<(String, String, IconData)> _guideItems = [
    (
      'Hola',
      'Mano abierta BIEN ARRIBA (sobre el hombro, junto a la cabeza) y muévela de lado a lado como saludando.',
      Icons.waving_hand_rounded,
    ),
    (
      '¿Cómo estás?',
      'Mano cerca de la cara (mejilla/barbilla) con un movimiento corto de lado a lado y cara de pregunta.',
      Icons.help_rounded,
    ),
    (
      'Yo',
      'Apunta o apoya la mano en tu pecho y mantenla quieta.',
      Icons.person_rounded,
    ),
    (
      'Bien',
      'Mano a la altura del pecho, palma al frente, totalmente quieta.',
      Icons.thumb_up_rounded,
    ),
    (
      'Sí',
      'Mano a la altura del pecho moviéndola arriba y abajo.',
      Icons.check_circle_rounded,
    ),
    (
      'No',
      'Mano a la altura del pecho moviéndola de lado a lado.',
      Icons.cancel_rounded,
    ),
    (
      'Gracias',
      'Mano cerca de la barbilla, quieta o alejándola suavemente hacia adelante.',
      Icons.favorite_rounded,
    ),
    (
      'Por favor / Dolor',
      'Junta las dos manos frente al cuerpo (a la altura del pecho = Dolor).',
      Icons.front_hand_rounded,
    ),
  ];

  @override
  void dispose() {
    _agent.latest.removeListener(_onAgentUpdate);
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
                    CameraCoverPreview(controller: _camera!)
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _showSignGuide,
                          tooltip: 'Guía de señas',
                          icon: const Icon(Icons.menu_book_rounded,
                              color: Colors.white),
                        ),
                        IconButton(
                          onPressed: _flip,
                          icon: const Icon(Icons.flip_camera_ios_rounded,
                              color: Colors.white),
                        ),
                      ],
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
                          Text(
                            _sentence.isEmpty
                                ? 'FRASE DEL AGENTE IA'
                                : 'FRASE · ${_agentSource == 'openai' ? 'GPT' : 'AGENTE'}',
                            style: const TextStyle(
                              color: Color(0xff27C7D9),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _sentence.isNotEmpty ? _sentence : _hint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                          if (_signsLine.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              _signsLine,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
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
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: Color(0xff27C7D9), size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'PALABRAS → FRASE',
                      style: TextStyle(
                        color: Color(0xffA8B8C0),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Text(
                    _agentSource == 'gemini' ? 'IA' : 'Local',
                    style: TextStyle(
                      color: _agentSource == 'gemini'
                          ? const Color(0xff2ECC71)
                          : Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _sentence.isNotEmpty ? _sentence : _hint,
                style: const TextStyle(
                  color: Color(0xff121B35),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_signsLine.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Señas: $_signsLine',
                  style: const TextStyle(
                    color: Color(0xff6B7C86),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final t =
                            _sentence.isNotEmpty ? _sentence : _hint;
                        if (t.isEmpty) return;
                        _voice.speak(t);
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
                    onPressed: _clear,
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
