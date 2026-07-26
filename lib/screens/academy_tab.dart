import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:conecta_lsb/services/settings_service.dart';
import 'package:conecta_lsb/services/sign_detection_service.dart';
import 'package:conecta_lsb/services/sign_guide.dart';
import 'package:conecta_lsb/widgets/camera_cover_preview.dart';
import 'package:conecta_lsb/widgets/hand_points_overlay.dart';

class AcademyCourse {
  final String id;
  final String title;
  final String desc;
  final String level;
  final IconData icon;
  final List<String> practices;

  const AcademyCourse({
    required this.id,
    required this.title,
    required this.desc,
    required this.level,
    required this.icon,
    required this.practices,
  });
}

/// Misma guía visual en Academia, Traducción y videollamada.
Map<String, List<String>> get signSteps => SignGuide.steps;

IconData signIcon(String phrase) => SignGuide.iconFor(phrase);

const academyCourses = [
  AcademyCourse(
    id: 'saludos',
    title: 'Saludos y preguntas',
    desc: 'Aprende Hola, ¿Cómo estás?, Gracias y Adiós con pasos claros.',
    level: 'Básico · Paso 1',
    icon: Icons.waving_hand_rounded,
    practices: ['Hola', 'Cómo', 'Gracias', 'Adiós'],
  ),
  AcademyCourse(
    id: 'respuestas',
    title: 'Respuestas rápidas',
    desc: 'Sí, No, Bien y Mal — para contestar en una conversación.',
    level: 'Básico · Paso 2',
    icon: Icons.thumb_up_alt_rounded,
    practices: ['Sí', 'No', 'Bien', 'Mal'],
  ),
  AcademyCourse(
    id: 'yo_necesito',
    title: 'Yo y necesidades',
    desc: 'Yo, Dolor, Comer, Beber, Dormir — pide ayuda o expresa necesidades.',
    level: 'Intermedio · Paso 3',
    icon: Icons.person_rounded,
    practices: ['Yo', 'Dolor', 'Comer', 'Beber', 'Dormir'],
  ),
];

/// Lista Academia LSB con prácticas e instrucciones.
class AcademyTab extends StatefulWidget {
  const AcademyTab({super.key});

  @override
  State<AcademyTab> createState() => _AcademyTabState();
}

class _AcademyTabState extends State<AcademyTab> {
  Map<String, double> _progress = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SettingsService.instance.loadAcademyProgress();
    if (mounted) setState(() => _progress = p);
  }

  void _openFullGuide() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
              '¿Qué debo hacer?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xff121B35),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '1) Elige un curso abajo.\n'
              '2) Lee los pasos de la seña.\n'
              '3) Haz el gesto frente a la cámara hasta que diga ¡Correcto!\n'
              '4) Continúa con la siguiente seña.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xff5A6E85),
                height: 1.45,
              ),
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
            const Text(
              'Consejos',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Color(0xff121B35),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Ponte a 1–2 metros con luz de frente.\n'
              '• Que se vean pecho, brazos y cara.\n'
              '• Mantén cada seña 1–2 segundos.\n'
              '• Si no detecta, mira los pasos otra vez y repite más lento.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xff5A6E85),
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Academia LSB',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xff121B35),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _openFullGuide,
                  tooltip: 'Cómo empezar',
                  icon: const Icon(Icons.menu_book_rounded,
                      color: Color(0xff27C7D9)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Aquí aprendes qué seña hacer y cómo mover las manos. '
              'Toca “Cómo empezar” o elige un curso.',
              style: TextStyle(fontSize: 15, color: Color(0xff5A6E85)),
            ),
            const SizedBox(height: 14),
            Material(
              color: const Color(0xffE5F7FF),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openFullGuide,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.school_rounded, color: Color(0xff27C7D9)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cómo empezar (guía con imágenes)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xff121B35),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Pasos + ilustraciones de Hola, Cómo estás, Yo…',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xff5A6E85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: Color(0xff27C7D9)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: academyCourses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final course = academyCourses[index];
                  final progress = _progress[course.id] ?? 0.0;
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    elevation: 1,
                    shadowColor: Colors.black12,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AcademyPracticeScreen(course: course),
                          ),
                        );
                        _load();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: const Color(0xffE5F7FF),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(course.icon,
                                      color: const Color(0xff27C7D9), size: 26),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        course.level,
                                        style: const TextStyle(
                                          color: Color(0xff27C7D9),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        course.title,
                                        style: const TextStyle(
                                          color: Color(0xff121B35),
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.play_circle_fill_rounded,
                                    color: Color(0xff27C7D9), size: 32),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              course.desc,
                              style: const TextStyle(
                                color: Color(0xff5A6E85),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: course.practices
                                  .map(
                                    (p) => Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(p == 'Cómo'
                                          ? '¿Cómo estás?'
                                          : p),
                                      labelStyle: const TextStyle(fontSize: 11),
                                      backgroundColor:
                                          const Color(0xffF0F7FA),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 6,
                                      backgroundColor: Colors.grey.shade100,
                                      valueColor:
                                          const AlwaysStoppedAnimation(
                                              Color(0xff27C7D9)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${(progress * 100).toInt()}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xff121B35),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              progress >= 1
                                  ? 'Completado · Toca para repetir'
                                  : 'Toca para ver pasos y practicar',
                              style: const TextStyle(
                                color: Color(0xff27C7D9),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AcademyPracticeScreen extends StatefulWidget {
  final AcademyCourse course;

  const AcademyPracticeScreen({super.key, required this.course});

  @override
  State<AcademyPracticeScreen> createState() => _AcademyPracticeScreenState();
}

class _AcademyPracticeScreenState extends State<AcademyPracticeScreen> {
  final _sign = SignDetectionService();
  CameraController? _camera;
  bool _ready = false;
  bool _busy = false;
  bool _learning = true; // primero enseña, luego cámara
  int _index = 0;
  final Set<String> _done = {};
  String _feedback = 'Lee los pasos y toca “Practicar con cámara”';

  String get _target => widget.course.practices[_index];
  List<String> get _steps => SignGuide.stepsFor(_target);
  String get _targetLabel => SignGuide.labelFor(_target);

  @override
  void initState() {
    super.initState();
    // La cámara se inicia al pasar a practicar
  }

  Future<void> _startCamera() async {
    if (_camera != null) {
      setState(() {
        _learning = false;
        _feedback = 'Haz la seña: $_targetLabel';
      });
      return;
    }
    await Permission.camera.request();
    await _sign.start();
    final cams = await availableCameras();
    if (cams.isEmpty) {
      if (mounted) {
        setState(() => _feedback = 'No hay cámara disponible');
      }
      return;
    }
    final front = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    _camera = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await _camera!.initialize();
    _sign.syncOrientation(_camera);
    await _camera!.startImageStream(_onFrame);
    if (mounted) {
      setState(() {
        _ready = true;
        _learning = false;
        _feedback = 'Haz la seña: $_targetLabel';
      });
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_learning || _busy || !_ready || _camera == null) return;
    _busy = true;
    try {
      _sign.syncOrientation(_camera);
      final r = await _sign.processCameraImage(
        image,
        camera: _camera!.description,
      );
      if (r == null || r.phrase.isEmpty || !mounted) return;
      if (r.phrase == _target) {
        _done.add(_target);
        final progress = _done.length / widget.course.practices.length;
        await SettingsService.instance
            .saveAcademyProgress(widget.course.id, progress);
        setState(() => _feedback = '¡Correcto! $_targetLabel');
        await Future.delayed(const Duration(milliseconds: 1000));
        if (!mounted) return;
        if (_index < widget.course.practices.length - 1) {
          setState(() {
            _index++;
            _learning = true; // enseña la siguiente antes de detectar
            _feedback = 'Nueva seña: $_targetLabel — lee cómo hacerla';
          });
        } else {
          setState(() => _feedback = '¡Curso completado! Vuelve al menú.');
        }
      } else {
        setState(() =>
            _feedback = 'Detecté "${r.phrase}". Objetivo: $_targetLabel');
      }
    } finally {
      _busy = false;
    }
  }

  void _showGuideImage() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Guía visual de señas',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                        SignGuide.asset,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _camera?.dispose();
    _sign.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _done.length / widget.course.practices.length;
    return Scaffold(
      backgroundColor: const Color(0xff0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xff0F172A),
        foregroundColor: Colors.white,
        title: Text(widget.course.title),
        actions: [
          IconButton(
            onPressed: _showGuideImage,
            tooltip: 'Ver imágenes',
            icon: const Icon(Icons.image_rounded),
          ),
        ],
      ),
      body: _learning ? _buildLearnPhase(progress) : _buildPracticePhase(progress),
    );
  }

  Widget _buildLearnPhase(double progress) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white12,
                color: const Color(0xff37C8F2),
              ),
              const SizedBox(height: 18),
              const Text(
                'APRENDE LA SEÑA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xff37C8F2),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(signIcon(_target),
                      color: const Color(0xff37C8F2), size: 36),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _targetLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Seña ${_index + 1} de ${widget.course.practices.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                        SignGuide.asset,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Cómo hacerla (sigue estos pasos)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...List.generate(_steps.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xff37C8F2).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xff37C8F2),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _steps[i],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              Text(
                _feedback,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _startCamera,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff37C8F2),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.videocam_rounded),
                label: const Text(
                  'Ya entendí — practicar con cámara',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPracticePhase(double progress) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(signIcon(_target), color: const Color(0xff37C8F2)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Practica: $_targetLabel',
                      style: const TextStyle(
                        color: Color(0xff37C8F2),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _learning = true;
                      _feedback = 'Repasa los pasos de $_targetLabel';
                    }),
                    child: const Text(
                      'Ver pasos',
                      style: TextStyle(color: Color(0xff37C8F2)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _steps.take(2).map((s) => '• $s').join('\n'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _feedback,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white12,
                color: const Color(0xff37C8F2),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _ready && _camera != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraCoverPreview(controller: _camera!),
                        HandPointsOverlay(frames: _sign.points),
                      ],
                    )
                  : const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xff37C8F2)),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.course.practices.map((p) {
              final ok = _done.contains(p);
              final current = p == _target;
              final label = p == 'Cómo' ? '¿Cómo estás?' : p;
              return Chip(
                avatar: Icon(
                  signIcon(p),
                  size: 16,
                  color: ok || current ? Colors.black87 : Colors.white70,
                ),
                label: Text(label),
                backgroundColor: ok
                    ? const Color(0xff2ECC71)
                    : (current
                        ? const Color(0xff37C8F2)
                        : Colors.white12),
                labelStyle: TextStyle(
                  color: ok || current ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
