import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:conecta_lsb/theme/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:conecta_lsb/services/sign_ai_agent.dart';
import 'package:conecta_lsb/services/sign_detection_service.dart';
import 'package:conecta_lsb/services/sign_guide.dart';
import 'package:conecta_lsb/services/voice_bridge_service.dart';
import 'package:conecta_lsb/widgets/camera_cover_preview.dart';
import 'package:conecta_lsb/widgets/hand_points_overlay.dart';
import 'package:conecta_lsb/widgets/tracker_checklist.dart';
import 'package:conecta_lsb/widgets/ui_kit.dart';

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
  List<String> _signs = const [];

  /// Sube con cada seña reconocida: dispara el destello + vibración.
  int _signCount = 0;
  String _sentence = '';
  String _agentSource = 'local';
  DateTime _lastSpeak = DateTime.fromMillisecondsSinceEpoch(0);
  String _spokenSentence = '';
  Timer? _speakTimer;

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
      _signs = out.signs;
      _sentence = out.sentence;
      _agentSource = out.source;
    });
  }

  /// Habla cuando el usuario termina de señar (frase completa, no por trozos).
  void _scheduleSpeak() {
    _speakTimer?.cancel();
    _speakTimer = Timer(const Duration(milliseconds: 850), () async {
      final out = await _agent.flush();
      if (!mounted) return;
      final sentence = out.sentence.trim();
      if (sentence.isEmpty) return;
      final now = DateTime.now();
      if (sentence == _spokenSentence &&
          now.difference(_lastSpeak) < const Duration(seconds: 4)) {
        return;
      }
      _spokenSentence = sentence;
      _lastSpeak = now;
      unawaited(_voice.speak(sentence));
    });
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
        // Estado en vivo sobre la cámara (siempre, aunque ya haya frase).
        // Calibración: el diagnóstico dice qué corregir (luz, distancia…).
        final advice = _sign.diagnostics.value.advice;
        final h = result.candidate.isNotEmpty
            ? 'Detectando «${SignGuide.labelFor(result.candidate)}»…'
            : (advice ?? 'Manos detectadas · haz la seña');
        if (_hint != h) {
          _hint = h;
          changed = true;
        }
        if (changed && mounted) setState(() {});
        return;
      }

      // Agente IA: arma palabras → frase en español
      final agentOut = await _agent.ingestSign(result.phrase);
      if (!mounted) return;

      setState(() {
        _signs = agentOut.signs;
        _sentence = agentOut.sentence;
        _agentSource = agentOut.source;
        _hint = 'Seña reconocida: ${SignGuide.labelFor(result.phrase)}';
        _signCount++;
      });

      // Leer recién cuando la frase queda completa (evita cortar cada seña)
      _scheduleSpeak();
    } finally {
      _busy = false;
    }
  }

  Future<void> _clear() async {
    _speakTimer?.cancel();
    _spokenSentence = '';
    _agent.clear();
    setState(() {
      _signs = const [];
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
                color: AppColors.ink,
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
                SignGuide.asset,
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
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(g.$3, color: AppColors.brand),
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
                              color: AppColors.ink,
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
    _speakTimer?.cancel();
    _agent.latest.removeListener(_onAgentUpdate);
    _camera?.dispose();
    _sign.stop();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildCameraCard()),
          const SizedBox(height: AppSpace.md),
          _buildSentenceCard(),
        ],
      ),
    );
  }

  /// Cámara: solo estado en vivo (la frase vive abajo, sin duplicarla).
  Widget _buildCameraCard() {
    final ready = _ready && _camera != null;
    return SignFlash(
      trigger: _signCount,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              CameraCoverPreview(controller: _camera!)
            else
              ColoredBox(
                color: AppColors.callBg,
                child: _denied
                    ? const EmptyState(
                        dark: true,
                        illustration: Illustrations.cameraPermission,
                        title: 'Necesitamos tu cámara',
                        message: 'Actívala en Ajustes para traducir tus '
                            'señas LSB en vivo.',
                        actionLabel: 'Abrir ajustes',
                        actionIcon: Icons.settings_rounded,
                        onAction: openAppSettings,
                      )
                    : const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brandBright,
                        ),
                      ),
              ),
            if (ready)
              HandPointsOverlay(frames: _sign.points, mirror: _isFront),
            Positioned(
              top: AppSpace.md,
              left: AppSpace.md,
              right: AppSpace.md,
              child: Row(
                children: [
                  Flexible(child: _liveBadge()),
                  const Spacer(),
                  _cameraAction(
                    icon: Icons.menu_book_rounded,
                    tooltip: 'Guía de señas',
                    onPressed: _showSignGuide,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  _cameraAction(
                    icon: Icons.cameraswitch_rounded,
                    tooltip: 'Cambiar cámara',
                    onPressed: _flip,
                  ),
                ],
              ),
            ),
            if (ready)
              Positioned(
                top: AppSpace.md + kMinTouch + AppSpace.sm,
                left: AppSpace.md,
                right: AppSpace.md,
                child:
                    TrackerChecklist(sign: _sign, handsVisible: _handsVisible),
              ),
            if (ready)
              Positioned(
                left: AppSpace.md,
                right: AppSpace.md,
                bottom: AppSpace.md,
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.md,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.callBg.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _handsVisible
                              ? Icons.front_hand_rounded
                              : Icons.accessibility_new_rounded,
                          color: _handsVisible
                              ? AppColors.successBright
                              : Colors.white70,
                          size: 22,
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Text(
                            _hint,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _liveBadge() {
    final live = _handsVisible;
    return _pill(
      icon: live ? Icons.circle : Icons.search_rounded,
      iconSize: live ? 10 : 16,
      label: live
          ? 'LSB en vivo'
          : (_bodyVisible ? 'Buscando manos' : _liveStatus),
      color: live ? AppColors.success : AppColors.callBg.withValues(alpha: 0.7),
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required Color color,
    double iconSize = 16,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: iconSize),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.callBg.withValues(alpha: 0.7),
        foregroundColor: Colors.white,
        minimumSize: const Size(kMinTouch, kMinTouch),
      ),
      icon: Icon(icon),
    );
  }

  /// Frase armada + señas como chips + acciones.
  Widget _buildSentenceCard() {
    final t = Theme.of(context).textTheme;
    final hasSentence = _sentence.isNotEmpty;
    final fromAi = _agentSource != 'local';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Tu frase',
                  style: t.labelLarge?.copyWith(
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (hasSentence)
                  Tooltip(
                    message: fromAi
                        ? 'Frase mejorada por el agente IA'
                        : 'Frase armada en el teléfono (sin conexión a IA)',
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        fromAi ? Icons.auto_awesome : Icons.phone_android,
                        size: 16,
                        color: AppColors.ink,
                      ),
                      label: Text(fromAi ? 'IA' : 'Local'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                hasSentence
                    ? _sentence
                    : 'Haz una seña y aquí aparecerá la frase',
                style:
                    (hasSentence ? t.headlineSmall : t.titleMedium)?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: hasSentence ? AppColors.ink : AppColors.inkMuted,
                  height: 1.25,
                ),
              ),
            ),
            if (_signs.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final sgn in _signs)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        SignGuide.iconFor(sgn),
                        size: 16,
                        color: AppColors.ink,
                      ),
                      label: Text(SignGuide.labelFor(sgn)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        hasSentence ? () => _voice.speak(_sentence) : null,
                    icon: const Icon(Icons.volume_up_rounded),
                    label: const Text('Leer en voz alta'),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                OutlinedButton.icon(
                  onPressed: hasSentence ? _clear : null,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Nueva'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
