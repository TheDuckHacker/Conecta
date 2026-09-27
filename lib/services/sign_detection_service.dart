import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'hand_tracker.dart';

/// Resultado de detección de señas en español (enfoque solo manos).
class SignDetectionResult {
  final String phrase;
  final double confidence;
  final bool handsVisible;
  final bool bodyVisible;
  final String status; // buscando | manos | seña

  /// Seña que va ganando la votación (aún sin confirmar). Vacío si ninguna.
  final String candidate;

  const SignDetectionResult({
    required this.phrase,
    required this.confidence,
    required this.handsVisible,
    this.bodyVisible = false,
    this.status = 'buscando',
    this.candidate = '',
  });
}

/// Puntos de manos/brazos del último frame, normalizados (0..1) sobre la
/// imagen ya rotada. Sirve para dibujarlos encima de la cámara.
class HandPointsFrame {
  final List<Offset?> points;
  final double aspect; // ancho / alto de la imagen rotada

  /// Esqueleto de dedos (21 puntos por mano) de MediaPipe Hand Landmarker.
  final List<List<Offset>> hands;

  const HandPointsFrame({
    required this.points,
    required this.aspect,
    this.hands = const [],
  });

  /// Conexiones de los 21 puntos de MediaPipe (dedos + palma).
  static const List<List<int>> fingerBones = [
    [0, 1], [1, 2], [2, 3], [3, 4], //
    [0, 5], [5, 6], [6, 7], [7, 8], //
    [5, 9], [9, 10], [10, 11], [11, 12], //
    [9, 13], [13, 14], [14, 15], [15, 16], //
    [13, 17], [0, 17], [17, 18], [18, 19], [19, 20],
  ];

  /// Huesos del brazo (hombro-codo-muñeca) para dibujar junto a los dedos.
  static const List<List<int>> armBones = [
    [0, 1],
    [1, 2],
    [6, 7],
    [7, 8],
    [0, 6],
  ];

  /// Índices en [points]: 0..5 mano izquierda, 6..11 mano derecha
  /// (hombro, codo, muñeca, pulgar, índice, meñique).
  static const List<List<int>> bones = [
    [0, 1],
    [1, 2],
    [2, 3],
    [2, 4],
    [2, 5],
    [4, 5],
    [6, 7],
    [7, 8],
    [8, 9],
    [8, 10],
    [8, 11],
    [10, 11],
    [0, 6],
  ];

  static const List<int> handIndexes = [2, 3, 4, 5, 8, 9, 10, 11];
}

/// Tipo de movimiento de la mano en la ventana reciente
/// (modelo Hold–Movement–Hold de la fonología de lenguas de señas).
enum MotionKind {
  /// Sin manos o sin datos suficientes.
  none,

  /// Postura sostenida (Yo, Bien, Gracias, Comer, Mal, Por favor…).
  hold,

  /// Vaivén lateral (Hola, Cómo, No, Adiós).
  waveX,

  /// Movimiento arriba-abajo (Sí).
  waveY,

  /// Transición rápida entre dos señas ("movement epenthesis"): NO es una
  /// seña y no se clasifica.
  transition,

  /// Movimiento lento que aún no se define.
  moving,
}

/// Lo que el motor "entiende" en este instante (para el panel de
/// entendimiento y para depurar).
class SignUnderstanding {
  final MotionKind motion;

  /// Velocidad de la mano (anchos de hombro por segundo).
  final double speed;

  /// Frames por segundo que realmente llegan al clasificador.
  final double fps;

  /// Señas con mayor evidencia acumulada (0..1), de mayor a menor.
  final List<(String, double)> top;

  const SignUnderstanding({
    this.motion = MotionKind.none,
    this.speed = 0,
    this.fps = 0,
    this.top = const [],
  });
}

/// Estado del tracker para calibrar en vivo: qué ve la cámara ahora.
class TrackerDiagnostics {
  /// ML Kit ve hombros y cara en este frame.
  final bool body;

  /// No se ven los hombros, pero se usa la última referencia (≤ 4 s).
  final bool bodyFromMemory;

  /// Manos que ve MediaPipe (0 si el tracker de dedos no está activo).
  final int hands;

  /// Brillo medio de la imagen (0-255). -1 = aún sin medir.
  final double luma;

  /// MediaPipe activo: solo entonces [hands] es confiable.
  final bool fingerTracking;

  const TrackerDiagnostics({
    this.body = false,
    this.bodyFromMemory = false,
    this.hands = 0,
    this.luma = -1,
    this.fingerTracking = false,
  });

  bool get lowLight => luma >= 0 && luma < 70;
  bool get bodyOk => body || bodyFromMemory;

  /// Lo más importante a corregir, en orden. null = todo bien.
  String? get advice {
    if (lowLight) {
      return 'Poca luz: enciende una luz o ponte frente a una ventana';
    }
    if (!bodyOk && hands > 0) {
      return 'Aléjate un poco: necesito ver tus hombros';
    }
    if (!bodyOk) return 'Colócate de frente, con cabeza y hombros visibles';
    if (fingerTracking && hands == 0) {
      return 'Sube una mano a la altura del pecho';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is TrackerDiagnostics &&
      other.body == body &&
      other.bodyFromMemory == bodyFromMemory &&
      other.hands == hands &&
      (other.luma - luma).abs() < 8;

  @override
  int get hashCode => Object.hash(body, bodyFromMemory, hands, luma ~/ 8);
}

/// Detección estilo [GestureGuide](https://github.com/Innominados/LenguajeSenas_Web):
/// 1. Mientras hay manos → acumular frames de la seña
/// 2. Confirmar seña estable
/// 3. Emitir UNA frase
/// 4. Limpiar buffer → listo para la siguiente seña
///
/// Todas las medidas se expresan en "unidades de hombro" (ancho de hombros = 1)
/// para que funcione igual de cerca o de lejos de la cámara.
class SignDetectionService {
  PoseDetector? _detector;

  /// MediaPipe Hand Landmarker: 21 puntos por mano (forma de los dedos).
  final HandTracker _handTracker = HandTracker();

  /// true si el tracker de dedos (MediaPipe) está activo en este dispositivo.
  bool get fingerTracking => _handTracker.available;

  /// Diagnóstico en vivo para la calibración (cuerpo / manos / luz).
  final ValueNotifier<TrackerDiagnostics> diagnostics =
      ValueNotifier(const TrackerDiagnostics());

  /// Última referencia de cuerpo SIN manos (hombros, cara, caderas). Permite
  /// seguir clasificando si la persona se acerca y salen los hombros.
  Pose? _bodyRef;
  DateTime _bodyRefAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _bodyRefTtl = Duration(seconds: 4);
  static const _bodyTypes = {
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.nose,
    PoseLandmarkType.leftMouth,
    PoseLandmarkType.rightMouth,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
  };

  int _lumaTick = 0;
  double _luma = -1;

  /// MediaPipe devuelve los puntos SIN rotar (coordenadas del sensor).
  /// Se autocalibra la orientación comparando su muñeca con la de ML Kit
  /// en 8 combinaciones (giro k·90° horario, con/sin espejo).
  int _mpRotKey = -1;
  final List<double> _mpErr = List<double>.filled(8, 0);
  int _mpSamples = 0;
  int? _mpCombo;

  /// Señas de vaivén: un mismo movimiento continuo puede cruzar el umbral
  /// entre ellas y alternar Hola ↔ Cómo en bucle.
  static const _waveFamily = {'Hola', 'Cómo', 'Adiós', 'No'};

  /// La mano se detuvo (o salió) desde la última seña emitida.
  bool _pausedSinceCommit = true;
  bool _busy = false;
  final List<_HandPose> _history = [];

  /// Posición suavizada (EMA) de la mano activa, paralela a [_history].
  /// Filtra el temblor de ML Kit para que no cuente como vaivén.
  final List<double> _smoothX = [];
  final List<double> _smoothY = [];
  static const double _emaAlpha = 0.7;

  /// Frames seguidos sin manos. Se tolera una pérdida breve antes de
  /// descartar la seña en curso.
  int _missFrames = 0;
  static const int _maxMissFrames = 3;

  /// Puntos del último frame para dibujar el esqueleto de las manos.
  final ValueNotifier<HandPointsFrame?> points =
      ValueNotifier<HandPointsFrame?>(null);

  String? _lastEmitted;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  // ---- Motor de señas (todo en milisegundos: igual a 5 fps que a 30 fps)

  /// Marca de tiempo de cada muestra de [_history].
  final List<int> _times = [];

  /// Evidencia acumulada por seña (EMA con constante de tiempo [_tauMs]).
  final Map<String, double> _evidence = {};
  static const double _tauMs = 260;

  /// Seña líder y desde cuándo lo es (para exigir un tiempo mínimo).
  String? _leader;
  int _leaderSinceMs = 0;

  /// Para emitir: evidencia ≥ [_commitLevel], ventaja sobre la segunda
  /// ≥ [_commitMargin] y líder durante ≥ [_holdDwellMs] / [_moveDwellMs].
  static const double _commitLevel = 0.55;
  static const double _commitMargin = 0.15;
  static const int _holdDwellMs = 380;
  static const int _moveDwellMs = 220;

  /// Ventanas de análisis.
  static const int _motionWindowMs = 750;
  static const int _speedWindowMs = 240;

  /// Por encima de esta velocidad sin oscilación = transición.
  static const double _transitionSpeed = 1.6;

  int _lastFrameMs = 0;
  double _fps = 0;

  /// Panel de entendimiento: qué movimiento ve y qué señas evalúa.
  final ValueNotifier<SignUnderstanding> understanding =
      ValueNotifier(const SignUnderstanding());

  static const _staticSigns = {
    'Yo',
    'Bien',
    'Gracias',
    'Comer',
    'Mal',
    'Por favor',
    'Dolor',
  };

  List<String> _mslTerms = const [];
  List<String> _quickPhrases = const [];
  int deviceOrientationDegrees = 0;

  List<String> get mslTerms => _mslTerms;
  List<String> get quickPhrases =>
      _quickPhrases.isNotEmpty ? _quickPhrases : _fallbackQuick;

  static const _fallbackQuick = [
    'Hola',
    'Sí',
    'No',
    'Bien',
    'Mal',
    'Yo',
    'Gracias',
    'Por favor',
    'Dolor',
    'Doctor',
    'Hoy',
    'Comer',
    'Beber',
    'Dormir',
    'Adiós',
  ];

  Future<void> start() async {
    _detector ??= PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );
    await _handTracker.start();
    await _loadVocabulary();
  }

  Future<void> _loadVocabulary() async {
    try {
      final termsRaw = await rootBundle.loadString('assets/msl/terms.txt');
      _mslTerms = termsRaw
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final vocabRaw =
          await rootBundle.loadString('assets/msl/vocabulary.json');
      final map = jsonDecode(vocabRaw) as Map<String, dynamic>;
      final qp = map['quickPhrases'];
      if (qp is List) {
        _quickPhrases = qp.map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint('MSL vocab: $e');
      _quickPhrases = _fallbackQuick;
    }
  }

  Future<void> stop() async {
    await _detector?.close();
    _detector = null;
    await _handTracker.stop();
    _bodyRef = null;
    _mpRotKey = -1;
    _resetGesture();
    _history.clear();
    points.value = null;
  }

  void _resetGesture() {
    _history.clear();
    _times.clear();
    _smoothX.clear();
    _smoothY.clear();
    _evidence.clear();
    _leader = null;
  }

  /// Pérdida de manos: solo reinicia si dura más de [_maxMissFrames].
  void _onHandsMissing() {
    _missFrames++;
    if (_missFrames >= _maxMissFrames) {
      _resetGesture();
      _pausedSinceCommit = true;
    }
  }

  void _pushSample(_HandPose sample, int nowMs) {
    _history.add(sample);
    _times.add(nowMs);
    final x = sample.activeHandX;
    final y = sample.activeHandY;
    if (_smoothX.isEmpty) {
      _smoothX.add(x);
      _smoothY.add(y);
    } else {
      _smoothX.add(_emaAlpha * x + (1 - _emaAlpha) * _smoothX.last);
      _smoothY.add(_emaAlpha * y + (1 - _emaAlpha) * _smoothY.last);
    }
    // Guardar ~1.5 s (o 45 muestras) de historia.
    while (_history.length > 45 || (nowMs - _times.first) > 1500) {
      _history.removeAt(0);
      _times.removeAt(0);
      _smoothX.removeAt(0);
      _smoothY.removeAt(0);
    }
  }

  void syncOrientation(CameraController? camera) {
    if (camera == null || !camera.value.isInitialized) return;
    switch (camera.value.deviceOrientation) {
      case DeviceOrientation.portraitUp:
        deviceOrientationDegrees = 0;
      case DeviceOrientation.landscapeLeft:
        deviceOrientationDegrees = 90;
      case DeviceOrientation.portraitDown:
        deviceOrientationDegrees = 180;
      case DeviceOrientation.landscapeRight:
        deviceOrientationDegrees = 270;
    }
  }

  Future<SignDetectionResult?> processCameraImage(
    CameraImage image, {
    required CameraDescription camera,
  }) async {
    // Dedos: MediaPipe corre en paralelo (asíncrono, con su propio límite).
    _handTracker.feed(image, camera.sensorOrientation);
    if (_detector == null || _busy) return null;

    _busy = true;
    try {
      final rotation = _rotationForCamera(camera);
      final input = _toInputImage(image, rotation);
      if (input == null) {
        return const SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: false,
          status: 'error_formato',
        );
      }

      final poses = await _detector!.processImage(input);
      _sampleLuma(image);

      // ML Kit devuelve los puntos sobre la imagen YA rotada: en vertical hay
      // que intercambiar ancho/alto o las medidas salen deformadas.
      final rotated = _rotatedSize(image, rotation);

      // Cuerpo: en vivo si se ven hombros + nariz; si no, la última
      // referencia (solo si hay manos que clasificar y es reciente).
      final now = DateTime.now();
      final livePose = poses.isEmpty ? null : poses.first;
      final hands = _orientHands(
        _handTracker.hands,
        rotation.rawValue,
        livePose,
        rotated.width,
        rotated.height,
      );
      final liveBody = livePose != null && _hasBody(livePose);
      if (liveBody) {
        _bodyRef = _bodyOnly(livePose);
        _bodyRefAt = now;
      }
      final memBody = !liveBody &&
          hands.isNotEmpty &&
          _bodyRef != null &&
          now.difference(_bodyRefAt) < _bodyRefTtl;
      diagnostics.value = TrackerDiagnostics(
        body: liveBody,
        bodyFromMemory: memBody,
        hands: hands.length,
        luma: _luma,
        fingerTracking: _handTracker.available,
      );

      final pose = liveBody ? livePose : (memBody ? _bodyRef : null);
      if (pose == null) {
        _onHandsMissing();
        // Sin referencia de cuerpo no se puede ubicar la seña, pero SÍ se
        // dibujan los dedos para que la persona vea que su mano se detecta.
        points.value = hands.isEmpty
            ? null
            : HandPointsFrame(
                points: List<Offset?>.filled(12, null),
                aspect: rotated.width / rotated.height,
                hands: hands.map((h) => h.points).toList(),
              );
        return SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: hands.isNotEmpty,
          bodyVisible: false,
          status: hands.isNotEmpty ? 'manos_sin_cuerpo' : 'buscando',
        );
      }

      final sample = _HandPose.fromPose(
        pose,
        imageWidth: rotated.width,
        imageHeight: rotated.height,
        hands: hands,
      );

      points.value = sample?.frame;

      if (sample == null || !sample.anyHandVisible) {
        _onHandsMissing();
        return const SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: false,
          bodyVisible: true,
          status: 'buscando',
        );
      }

      final nowMs = now.millisecondsSinceEpoch;
      _missFrames = 0;
      _trackFps(nowMs);
      _pushSample(sample, nowMs);

      final m = _motion(nowMs);
      if (m.kind == MotionKind.hold) _pausedSinceCommit = true;

      // Transición entre señas: no aporta evidencia a ninguna.
      final scores = m.kind == MotionKind.transition
          ? const <String, double>{}
          : _score(sample, m);
      _integrate(scores, nowMs);

      final ranked = _evidence.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      understanding.value = SignUnderstanding(
        motion: m.kind,
        speed: m.speed,
        fps: _fps,
        top: [for (final e in ranked.take(3)) (e.key, e.value)],
      );

      final best = ranked.isEmpty ? null : ranked.first;
      final second = ranked.length > 1 ? ranked[1].value : 0.0;
      if (best != null &&
          best.value >= _commitLevel &&
          best.value - second >= _commitMargin &&
          best.key == _leader &&
          nowMs - _leaderSinceMs >=
              (_staticSigns.contains(best.key) ? _holdDwellMs : _moveDwellMs)) {
        return _commit(best.key, best.value);
      }

      return SignDetectionResult(
        phrase: '',
        confidence: best?.value ?? 0,
        handsVisible: true,
        bodyVisible: true,
        status: 'manos',
        candidate: (best != null && best.value >= 0.3) ? best.key : '',
      );
    } catch (e) {
      debugPrint('SignDetection: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  static Offset _orient(Offset p, int combo) {
    var x = p.dx;
    var y = p.dy;
    switch (combo % 4) {
      case 1:
        (x, y) = (1 - y, x);
      case 2:
        (x, y) = (1 - x, 1 - y);
      case 3:
        (x, y) = (y, 1 - x);
    }
    if (combo >= 4) x = 1 - x;
    return Offset(x, y);
  }

  /// Lleva las manos de MediaPipe al mismo marco que ML Kit (imagen rotada).
  List<HandShape> _orientHands(
    List<HandShape> raw,
    int rotDeg,
    Pose? pose,
    double w,
    double h,
  ) {
    if (raw.isEmpty) return raw;
    if (rotDeg != _mpRotKey) {
      _mpRotKey = rotDeg;
      _mpErr.fillRange(0, 8, 0);
      _mpSamples = 0;
      _mpCombo = null;
    }
    if (_mpCombo == null && pose != null) {
      final wrists = [PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist]
          .map((t) => pose.landmarks[t])
          .whereType<PoseLandmark>()
          .where((l) => l.likelihood >= 0.5)
          .map((l) => Offset(l.x / w, l.y / h))
          .toList();
      if (wrists.isNotEmpty) {
        for (var c = 0; c < 8; c++) {
          for (final hs in raw) {
            final p = _orient(hs.points[0], c);
            _mpErr[c] += wrists.map((wr) => (p - wr).distance).reduce(min);
          }
        }
        if (++_mpSamples >= 8) {
          var best = 0;
          for (var c = 1; c < 8; c++) {
            if (_mpErr[c] < _mpErr[best]) best = c;
          }
          _mpCombo = best;
          debugPrint('HandTracker orientación calibrada: combo $best '
              '(rot ML Kit $rotDeg°, error ${(_mpErr[best] / _mpSamples).toStringAsFixed(3)})');
        }
      }
    }
    // Mientras calibra: girar como ML Kit (el ejemplo del plugin rota por
    // sensorOrientation al dibujar).
    final combo = _mpCombo ?? (rotDeg ~/ 90) % 4;
    return raw.map((hs) => hs.map((p) => _orient(p, combo))).toList();
  }

  bool _hasBody(Pose pose) {
    bool ok(PoseLandmarkType t, double min) =>
        (pose.landmarks[t]?.likelihood ?? 0) >= min;
    return ok(PoseLandmarkType.leftShoulder, 0.2) &&
        ok(PoseLandmarkType.rightShoulder, 0.2) &&
        ok(PoseLandmarkType.nose, 0.1);
  }

  /// Copia solo con cuerpo: las muñecas viejas no deben contar como manos.
  Pose _bodyOnly(Pose pose) => Pose(
        landmarks: {
          for (final e in pose.landmarks.entries)
            if (_bodyTypes.contains(e.key)) e.key: e.value,
        },
      );

  /// Brillo medio del plano Y (1 de cada 10 frames, muestreo disperso).
  void _sampleLuma(CameraImage image) {
    if (_lumaTick++ % 10 != 0 || image.planes.isEmpty) return;
    final y = image.planes.first.bytes;
    final ySize = min(y.length, image.width * image.height);
    if (ySize <= 0) return;
    var sum = 0;
    var n = 0;
    for (var i = 0; i < ySize; i += 97) {
      sum += y[i];
      n++;
    }
    final v = sum / n;
    _luma = _luma < 0 ? v : _luma * 0.6 + v * 0.4;
  }

  // ===================================================================
  // Motor de señas
  //
  // 1. Segmentación: cada instante se etiqueta como Hold (postura quieta),
  //    WaveX / WaveY (movimiento de la seña) o Transition (la mano viaja
  //    rápido de una seña a otra: "movement epenthesis", no es seña).
  // 2. Puntuación: cada seña recibe un puntaje continuo 0..1 =
  //    zona × movimiento × forma de mano. Nada de "gana el primer if".
  // 3. Integración temporal: la evidencia de cada seña es una media móvil
  //    en TIEMPO (τ = 260 ms), igual a 5 fps que a 30 fps.
  // 4. Decisión con margen: se emite solo si la mejor supera a la segunda
  //    por ≥ 0.15 y lleva liderando un tiempo mínimo. Ambigüedad → espera.
  // ===================================================================

  void _trackFps(int nowMs) {
    if (_lastFrameMs > 0) {
      final dt = nowMs - _lastFrameMs;
      if (dt > 0 && dt < 2000) {
        final inst = 1000 / dt;
        _fps = _fps == 0 ? inst : _fps * 0.85 + inst * 0.15;
      }
    }
    _lastFrameMs = nowMs;
  }

  /// Índice de la primera muestra dentro de los últimos [ms].
  int _startWithin(int nowMs, int ms) {
    var i = _times.length - 1;
    while (i > 0 && nowMs - _times[i - 1] <= ms) {
      i--;
    }
    return i;
  }

  ({
    MotionKind kind,
    double ampX,
    double ampY,
    int peaksX,
    double speed,
  }) _motion(int nowMs) {
    if (_smoothX.length < 3) {
      return (
        kind: MotionKind.none,
        ampX: 0.0,
        ampY: 0.0,
        peaksX: 0,
        speed: 0.0,
      );
    }
    final a = _startWithin(nowMs, _motionWindowMs);
    final xs = _smoothX.sublist(a);
    final ys = _smoothY.sublist(a);
    final ampX = xs.reduce(max) - xs.reduce(min);
    final ampY = ys.reduce(max) - ys.reduce(min);

    // Cambios de dirección reales (ignora temblor < 0.025).
    var peaks = 0;
    var lastDir = 0;
    for (var k = 1; k < xs.length; k++) {
      final d = xs[k] - xs[k - 1];
      if (d.abs() < 0.025) continue;
      final dir = d > 0 ? 1 : -1;
      if (lastDir != 0 && dir != lastDir) peaks++;
      lastDir = dir;
    }

    // Velocidad reciente (anchos de hombro / s).
    final b = _startWithin(nowMs, _speedWindowMs);
    final dtMs = _times.last - _times[b];
    final dist = Offset(
      _smoothX.last - _smoothX[b],
      _smoothY.last - _smoothY[b],
    ).distance;
    final speed = dtMs > 0 ? dist / (dtMs / 1000) : 0.0;

    final MotionKind kind;
    if (peaks >= 1 && ampX >= 0.06 && ampX >= ampY * 0.8) {
      kind = MotionKind.waveX;
    } else if (ampY >= 0.12 && ampY > ampX * 1.2) {
      kind = MotionKind.waveY;
    } else if (speed > _transitionSpeed) {
      kind = MotionKind.transition;
    } else if (ampX < 0.10 && ampY < 0.12) {
      kind = MotionKind.hold;
    } else {
      kind = MotionKind.moving;
    }
    return (kind: kind, ampX: ampX, ampY: ampY, peaksX: peaks, speed: speed);
  }

  /// Rampa lineal 0→1 entre [lo] y [hi].
  static double _ramp(double v, double lo, double hi) =>
      ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

  static double _b(bool v, [double no = 0.0]) => v ? 1.0 : no;

  /// Puntaje 0..1 de cada seña = zona × movimiento × forma.
  Map<String, double> _score(
    _HandPose s,
    ({
      MotionKind kind,
      double ampX,
      double ampY,
      int peaksX,
      double speed,
    }) m,
  ) {
    final shape = s.activeShape;
    // Sin MediaPipe la forma es desconocida: factor neutro 0.75.
    double shapeIs(bool Function(HandShape) f, [double unknown = 0.75]) =>
        shape == null ? unknown : (f(shape) ? 1.0 : 0.15);

    final hold = _b(m.kind == MotionKind.hold);
    final waveX =
        m.kind == MotionKind.waveX ? min(1.0, 0.5 + 0.5 * m.peaksX) : 0.0;
    final waveY = _b(m.kind == MotionKind.waveY);

    // Vaivén amplio vs corto: bandas que se solapan (no un corte duro).
    final wide = _ramp(m.ampX, 0.13, 0.24);
    final short = _ramp(m.ampX, 0.05, 0.09) * (1 - _ramp(m.ampX, 0.19, 0.27));

    final high = s.handAboveHead;
    final face = s.handInFaceZone;
    final open = shapeIs((h) => h.isOpen);
    final notFist = shapeIs((h) => !h.isFist, 0.85);
    final pointing = shapeIs((h) => h.indexOnly, 0.6);
    final bunched = shapeIs((h) => !h.isOpen, 0.7);

    final out = <String, double>{
      // Mano abierta arriba / junto a la cabeza + vaivén amplio.
      'Hola': (high ? 1.0 : (face ? 0.7 : 0.0)) * waveX * wide * open,
      // Mano frente a la cara + vaivén corto.
      'Cómo': _b(face) * _b(!high, 0.3) * waveX * short * notFist,
      // Media altura (más baja que Hola) + vaivén.
      'Adiós': _b(s.handUp && !high && !face) * waveX * wide * open,
      // Pecho + vaivén amplio con mano plana.
      'No': _b(s.handMid) * waveX * _ramp(m.ampX, 0.16, 0.26) * open,
      // Pulgar arriba (con dedos) o pecho + arriba/abajo.
      'Sí': max(
        (shape?.thumbUp ?? false) && !high
            ? (m.kind == MotionKind.transition ? 0.0 : 0.95)
            : 0.0,
        _b(s.handMid) * waveY * _ramp(m.ampY, 0.12, 0.2),
      ),
      // Índice al centro del pecho, quieta.
      'Yo': _b(s.handOnChest) * hold * pointing,
      // Pecho/hombro, palma abierta al frente, quieta.
      'Bien': _b(s.handMid && !face && !s.handOnChest, 0.4) *
          _b(s.handMid) *
          hold *
          open *
          (1 - (shape?.indexOnly ?? false ? 0.8 : 0.0)),
      // Mano cerca de la cara/barbilla, quieta.
      'Gracias': _b(face && !high && !s.handNearMouth, 0.5) *
          _b(face) *
          hold *
          notFist,
      // Mano en la boca, dedos juntos, quieta.
      'Comer': _b(s.handNearMouth) * hold * bunched,
      // Mano baja delante de la cadera, quieta.
      'Mal': _b(s.handLow) * hold,
      // Dos manos juntas frente al cuerpo, quietas.
      'Por favor': _b(s.handsTogether && !s.handLow && !s.bothHandsMid) * hold,
      'Dolor': _b(s.handsTogether && s.bothHandsMid) * hold,
    };
    return out;
  }

  /// Evidencia(t) = evidencia(t−dt)·(1−α) + puntaje·α, α = 1 − e^(−dt/τ).
  void _integrate(Map<String, double> scores, int nowMs) {
    final dt = _times.length >= 2
        ? (_times.last - _times[_times.length - 2]).clamp(1, 500)
        : 60;
    final alpha = 1 - exp(-dt / _tauMs);
    final keys = {..._evidence.keys, ...scores.keys};
    for (final k in keys) {
      final prev = _evidence[k] ?? 0.0;
      final next = prev * (1 - alpha) + (scores[k] ?? 0.0) * alpha;
      if (next < 0.02) {
        _evidence.remove(k);
      } else {
        _evidence[k] = next;
      }
    }
    // Seguir al líder (para el tiempo mínimo de permanencia).
    String? lead;
    var bestV = 0.0;
    _evidence.forEach((k, v) {
      if (v > bestV) {
        bestV = v;
        lead = k;
      }
    });
    if (lead != _leader) {
      _leader = lead;
      _leaderSinceMs = nowMs;
    }
  }

  /// Emite la seña con anti-repetición: misma seña 1.4 s; vaivén → otro
  /// vaivén sin pausa (Hola ↔ Cómo) 1.6 s; seña distinta 450 ms.
  SignDetectionResult _commit(String phrase, double evidence) {
    final now = DateTime.now();
    final same = phrase == _lastEmitted;
    final waveSwap = !same &&
        !_pausedSinceCommit &&
        _waveFamily.contains(phrase) &&
        _waveFamily.contains(_lastEmitted);
    final wait = same
        ? const Duration(milliseconds: 1400)
        : (waveSwap
            ? const Duration(milliseconds: 1600)
            : const Duration(milliseconds: 450));
    if (now.difference(_lastEmit) < wait) {
      return SignDetectionResult(
        phrase: '',
        confidence: evidence,
        handsVisible: true,
        status: 'seña',
        candidate: phrase,
      );
    }

    _lastEmitted = phrase;
    _lastEmit = now;
    _pausedSinceCommit = false;
    _resetGesture();

    return SignDetectionResult(
      phrase: phrase,
      confidence: evidence.clamp(0.0, 1.0),
      handsVisible: true,
      bodyVisible: true,
      status: 'seña',
    );
  }

  ({double width, double height}) _rotatedSize(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final turned = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    return turned ? (width: h, height: w) : (width: w, height: h);
  }

  InputImageRotation _rotationForCamera(CameraDescription camera) {
    final sensor = camera.sensorOrientation;
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensor) ??
          InputImageRotation.rotation0deg;
    }
    var rotationCompensation = deviceOrientationDegrees;
    if (camera.lensDirection == CameraLensDirection.front) {
      rotationCompensation = (sensor + rotationCompensation) % 360;
    } else {
      rotationCompensation = (sensor - rotationCompensation + 360) % 360;
    }
    return InputImageRotationValue.fromRawValue(rotationCompensation) ??
        InputImageRotation.rotation90deg;
  }

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
    try {
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          (Platform.isAndroid
              ? InputImageFormat.nv21
              : InputImageFormat.bgra8888);

      late Uint8List bytes;
      late int bytesPerRow;

      if (Platform.isAndroid) {
        if (image.planes.length == 1) {
          bytes = image.planes.first.bytes;
          bytesPerRow = image.planes.first.bytesPerRow;
        } else {
          final y = image.planes[0].bytes;
          final uv =
              image.planes.length > 1 ? image.planes[1].bytes : Uint8List(0);
          bytes = Uint8List(y.length + uv.length);
          bytes.setRange(0, y.length, y);
          if (uv.isNotEmpty) {
            bytes.setRange(y.length, bytes.length, uv);
          }
          bytesPerRow = image.planes.first.bytesPerRow;
        }
      } else {
        final WriteBuffer allBytes = WriteBuffer();
        for (final plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        bytes = allBytes.done().buffer.asUint8List();
        bytesPerRow = image.planes.first.bytesPerRow;
      }

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('toInputImage: $e');
      return null;
    }
  }
}

/// Postura de manos en unidades de hombro (ancho de hombros = 1.0).
class _HandPose {
  final double leftHandX;
  final double leftHandY;
  final double rightHandX;
  final double rightHandY;
  final double leftWristY;
  final double rightWristY;
  final double leftThumbY;
  final double rightThumbY;
  final double leftSpread; // apertura de la mano (índice ↔ meñique)
  final double rightSpread;
  final double noseX;
  final double noseY;
  final double mouthY;
  final double shoulderY;
  final double shoulderCenterX;
  final double hipY;
  final bool leftOk;
  final bool rightOk;
  final HandShape? leftShape;
  final HandShape? rightShape;
  final HandPointsFrame frame;

  const _HandPose({
    required this.leftHandX,
    required this.leftHandY,
    required this.rightHandX,
    required this.rightHandY,
    required this.leftWristY,
    required this.rightWristY,
    required this.leftThumbY,
    required this.rightThumbY,
    required this.leftSpread,
    required this.rightSpread,
    required this.noseX,
    required this.noseY,
    required this.mouthY,
    required this.shoulderY,
    required this.shoulderCenterX,
    required this.hipY,
    required this.leftOk,
    required this.rightOk,
    this.leftShape,
    this.rightShape,
    required this.frame,
  });

  bool get anyHandVisible => leftOk || rightOk;

  /// Mano de trabajo = la más levantada de las visibles.
  bool get _useLeft => leftOk && (!rightOk || leftHandY <= rightHandY);
  double get activeHandX => _useLeft ? leftHandX : rightHandX;
  double get activeHandY => _useLeft ? leftHandY : rightHandY;
  double get activeSpread => _useLeft ? leftSpread : rightSpread;
  double get activeWristY => _useLeft ? leftWristY : rightWristY;
  double get activeThumbY => _useLeft ? leftThumbY : rightThumbY;

  /// Forma de la mano activa (MediaPipe), si el tracker de dedos la vio.
  HandShape? get activeShape => _useLeft ? leftShape : rightShape;

  /// Mano por encima de la cabeza (zona de saludo).
  bool get handAboveHead => activeHandY < noseY - 0.25;

  /// Mano a la altura de la cara: mejilla, barbilla, frente.
  bool get handInFaceZone =>
      (activeHandX - noseX).abs() < 0.85 &&
      activeHandY > noseY - 0.45 &&
      activeHandY < noseY + 0.70;

  bool get handNearMouth =>
      (activeHandX - noseX).abs() < 0.55 && (activeHandY - mouthY).abs() < 0.28;

  /// Media altura: entre hombro y cara (Adiós).
  bool get handUp => activeHandY < shoulderY - 0.15;

  /// Zona del pecho (Bien, Sí, No, Yo).
  bool get handMid =>
      activeHandY > shoulderY - 0.15 && activeHandY < hipY - 0.20;

  bool get bothHandsMid =>
      leftOk &&
      rightOk &&
      leftHandY > shoulderY - 0.15 &&
      rightHandY > shoulderY - 0.15 &&
      leftHandY < hipY - 0.20 &&
      rightHandY < hipY - 0.20;

  bool get handsTogether =>
      leftOk &&
      rightOk &&
      (leftHandX - rightHandX).abs() < 0.45 &&
      (leftHandY - rightHandY).abs() < 0.45;

  /// Mano/índice sobre el centro del pecho (Yo).
  bool get handOnChest =>
      (activeHandX - shoulderCenterX).abs() < 0.42 &&
      activeHandY > shoulderY + 0.12 &&
      activeHandY < hipY - 0.25;

  /// Mano baja pero DELANTE del cuerpo (los brazos en reposo caen por fuera
  /// de la línea de los hombros y no deben contar como seña).
  bool get handLow =>
      activeHandY > hipY - 0.15 && (activeHandX - shoulderCenterX).abs() < 0.40;

  /// Pulgar arriba con mano cerrada (Sí).
  bool get thumbUp =>
      activeShape?.thumbUp ??
      (activeThumbY < activeWristY - 0.18 && activeSpread < 0.42);

  static _HandPose? fromPose(
    Pose pose, {
    required double imageWidth,
    required double imageHeight,
    List<HandShape> hands = const [],
  }) {
    PoseLandmark? lm(PoseLandmarkType t, [double minLikelihood = 0.12]) {
      final p = pose.landmarks[t];
      if (p == null) return null;
      return p.likelihood >= minLikelihood ? p : null;
    }

    final ls = lm(PoseLandmarkType.leftShoulder, 0.2);
    final rs = lm(PoseLandmarkType.rightShoulder, 0.2);
    final nose = lm(PoseLandmarkType.nose, 0.1);
    if (ls == null || rs == null || nose == null) return null;

    final lw = lm(PoseLandmarkType.leftWrist);
    final rw = lm(PoseLandmarkType.rightWrist);
    final li = lm(PoseLandmarkType.leftIndex);
    final ri = lm(PoseLandmarkType.rightIndex);
    final lt = lm(PoseLandmarkType.leftThumb);
    final rt = lm(PoseLandmarkType.rightThumb);
    final lp = lm(PoseLandmarkType.leftPinky);
    final rp = lm(PoseLandmarkType.rightPinky);
    final le = lm(PoseLandmarkType.leftElbow);
    final re = lm(PoseLandmarkType.rightElbow);
    final lh = lm(PoseLandmarkType.leftHip);
    final rh = lm(PoseLandmarkType.rightHip);
    final ml = lm(PoseLandmarkType.leftMouth, 0.1);
    final mr = lm(PoseLandmarkType.rightMouth, 0.1);

    final w = imageWidth <= 0 ? 1.0 : imageWidth;
    final h = imageHeight <= 0 ? 1.0 : imageHeight;

    // Asignar cada mano de MediaPipe al brazo de ML Kit más cercano.
    HandShape? leftShape;
    HandShape? rightShape;
    double distTo(HandShape hs, PoseLandmark? ref) {
      if (ref == null) return double.infinity;
      final dx = hs.palm.dx * w - ref.x;
      final dy = hs.palm.dy * h - ref.y;
      return sqrt(dx * dx + dy * dy);
    }

    for (final hs in hands) {
      final dl = distTo(hs, lw ?? li);
      final dr = distTo(hs, rw ?? ri);
      if (dl <= dr && leftShape == null) {
        leftShape = hs;
      } else if (rightShape == null) {
        rightShape = hs;
      } else {
        leftShape ??= hs;
      }
    }

    final leftOk = lw != null || li != null || leftShape != null;
    final rightOk = rw != null || ri != null || rightShape != null;

    // Escala = ancho de hombros en píxeles → todo es invariante a distancia.
    final dx = ls.x - rs.x;
    final dy = ls.y - rs.y;
    final shoulderPx = max(sqrt(dx * dx + dy * dy), w * 0.08);
    double u(double px) => px / shoulderPx;

    Offset? norm(PoseLandmark? p) =>
        p == null ? null : Offset(p.x / w, p.y / h);

    ({double x, double y})? palm(
      PoseLandmark? wrist,
      PoseLandmark? index,
      PoseLandmark? pinky,
      PoseLandmark? thumb,
    ) {
      final pts = [wrist, index, pinky, thumb].whereType<PoseLandmark>();
      if (pts.isEmpty) return null;
      var sx = 0.0;
      var sy = 0.0;
      for (final p in pts) {
        sx += p.x;
        sy += p.y;
      }
      return (x: sx / pts.length, y: sy / pts.length);
    }

    double spread(PoseLandmark? index, PoseLandmark? pinky) {
      if (index == null || pinky == null) return 0.5;
      final sx = index.x - pinky.x;
      final sy = index.y - pinky.y;
      return u(sqrt(sx * sx + sy * sy));
    }

    // Palma de MediaPipe (más precisa) si está; si no, la de ML Kit.
    ({double x, double y})? shapePalm(HandShape? hs) =>
        hs == null ? null : (x: hs.palm.dx * w, y: hs.palm.dy * h);
    final leftPalm = shapePalm(leftShape) ?? palm(lw, li, lp, lt);
    final rightPalm = shapePalm(rightShape) ?? palm(rw, ri, rp, rt);
    if (leftPalm == null && rightPalm == null) return null;

    final shoulderY = u((ls.y + rs.y) / 2);
    final hipY = (lh != null || rh != null)
        ? u(((lh?.y ?? rh!.y) + (rh?.y ?? lh!.y)) / 2)
        : shoulderY + 1.25;
    final mouthY = (ml != null || mr != null)
        ? u(((ml?.y ?? mr!.y) + (mr?.y ?? ml!.y)) / 2)
        : u(nose.y) + 0.25;

    final frame = HandPointsFrame(
      points: [
        norm(ls),
        norm(le),
        norm(lw),
        norm(lt),
        norm(li),
        norm(lp),
        norm(rs),
        norm(re),
        norm(rw),
        norm(rt),
        norm(ri),
        norm(rp),
      ],
      aspect: w / h,
      hands: hands.map((hs) => hs.points).toList(),
    );

    return _HandPose(
      leftHandX: u(leftPalm?.x ?? rightPalm!.x),
      leftHandY: u(leftPalm?.y ?? rightPalm!.y),
      rightHandX: u(rightPalm?.x ?? leftPalm!.x),
      rightHandY: u(rightPalm?.y ?? leftPalm!.y),
      leftWristY: u(lw?.y ?? leftPalm?.y ?? rightPalm!.y),
      rightWristY: u(rw?.y ?? rightPalm?.y ?? leftPalm!.y),
      leftThumbY: u(lt?.y ?? lw?.y ?? leftPalm?.y ?? rightPalm!.y),
      rightThumbY: u(rt?.y ?? rw?.y ?? rightPalm?.y ?? leftPalm!.y),
      leftSpread: spread(li, lp),
      rightSpread: spread(ri, rp),
      noseX: u(nose.x),
      noseY: u(nose.y),
      mouthY: mouthY,
      shoulderY: shoulderY,
      shoulderCenterX: u((ls.x + rs.x) / 2),
      hipY: hipY,
      leftOk: leftOk,
      rightOk: rightOk,
      leftShape: leftShape,
      rightShape: rightShape,
      frame: frame,
    );
  }
}
