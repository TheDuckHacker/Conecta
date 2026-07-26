import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Resultado de detección de señas en español (enfoque solo manos).
class SignDetectionResult {
  final String phrase;
  final double confidence;
  final bool handsVisible;
  final bool bodyVisible;
  final String status; // buscando | manos | seña

  const SignDetectionResult({
    required this.phrase,
    required this.confidence,
    required this.handsVisible,
    this.bodyVisible = false,
    this.status = 'buscando',
  });
}

/// Puntos de manos/brazos del último frame, normalizados (0..1) sobre la
/// imagen ya rotada. Sirve para dibujarlos encima de la cámara.
class HandPointsFrame {
  final List<Offset?> points;
  final double aspect; // ancho / alto de la imagen rotada

  const HandPointsFrame({required this.points, required this.aspect});

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
  bool _busy = false;
  final List<_HandPose> _history = [];

  /// Puntos del último frame para dibujar el esqueleto de las manos.
  final ValueNotifier<HandPointsFrame?> points =
      ValueNotifier<HandPointsFrame?>(null);

  /// Votos de la seña actual.
  final Map<String, int> _votes = {};
  int _gestureFrames = 0;
  String? _lastEmitted;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  /// Confirmación rápida: 2 frames bastan (~150 ms) para que fluya.
  static const int _minGestureFrames = 2;
  static const int _votesToConfirm = 2;

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
    _resetGesture();
    _history.clear();
    points.value = null;
  }

  void _resetGesture() {
    _votes.clear();
    _gestureFrames = 0;
    _history.clear();
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
      if (poses.isEmpty) {
        _resetGesture();
        points.value = null;
        return const SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: false,
          status: 'buscando',
        );
      }

      // ML Kit devuelve los puntos sobre la imagen YA rotada: en vertical hay
      // que intercambiar ancho/alto o las medidas salen deformadas.
      final rotated = _rotatedSize(image, rotation);

      final sample = _HandPose.fromPose(
        poses.first,
        imageWidth: rotated.width,
        imageHeight: rotated.height,
      );

      points.value = sample?.frame;

      if (sample == null || !sample.anyHandVisible) {
        _resetGesture();
        return const SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: false,
          bodyVisible: true,
          status: 'buscando',
        );
      }

      _history.add(sample);
      if (_history.length > 14) _history.removeAt(0);
      _gestureFrames++;

      final guess = _classify(sample);
      if (guess != null) {
        _votes[guess.phrase] = (_votes[guess.phrase] ?? 0) + 1;
      }

      final best = _bestVote();
      if (best != null &&
          (_votes[best]! >= _votesToConfirm) &&
          _gestureFrames >= _minGestureFrames) {
        return _commit(best);
      }

      return const SignDetectionResult(
        phrase: '',
        confidence: 0,
        handsVisible: true,
        bodyVisible: true,
        status: 'manos',
      );
    } catch (e) {
      debugPrint('SignDetection: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  String? _bestVote() {
    if (_votes.isEmpty) return null;
    var best = _votes.entries.first;
    for (final e in _votes.entries) {
      if (e.value > best.value) best = e;
    }
    if (best.value < 1) return null;
    return best.key;
  }

  SignDetectionResult _commit(String phrase) {
    final now = DateTime.now();
    // Misma seña: cooldown más largo para no repetir "Hola Hola Hola".
    // Seña distinta: casi inmediato, así "Hola → Cómo → Yo → Bien" fluye.
    final same = phrase == _lastEmitted;
    final wait = same
        ? const Duration(milliseconds: 1400)
        : const Duration(milliseconds: 220);
    if (now.difference(_lastEmit) < wait) {
      return const SignDetectionResult(
        phrase: '',
        confidence: 0.5,
        handsVisible: true,
        status: 'seña',
      );
    }

    _lastEmitted = phrase;
    _lastEmit = now;
    final conf =
        ((_votes[phrase] ?? 1) / max(1, _gestureFrames)).clamp(0.55, 0.95);

    _resetGesture();

    return SignDetectionResult(
      phrase: phrase,
      confidence: conf.toDouble(),
      handsVisible: true,
      bodyVisible: true,
      status: 'seña',
    );
  }

  /// Clasifica según la guía visual `assets/msl/guia_senas.png`.
  SignDetectionResult? _classify(_HandPose s) {
    if (_history.length < 2) return null;

    final wave = _horizontalAmp(); // vaivén lateral (unidades de hombro)
    final nod = _verticalAmp(); // movimiento arriba/abajo
    final peaks = _wavePeaks(); // cambios de dirección reales
    final still = wave < 0.11 && nod < 0.13;
    final high = s.handAboveHead;
    final face = s.handInFaceZone;

    // 1) HOLA — mano abierta arriba, junto a la cabeza + vaivén amplio
    if ((high || face) && wave >= 0.20 && peaks >= 1) {
      return _hit('Hola', 0.94);
    }
    if (high && wave >= 0.14) {
      return _hit('Hola', 0.85);
    }

    // 2) ¿CÓMO ESTÁS? — mano frente a la cara + vaivén CORTO
    if (face && wave >= 0.07 && wave < 0.20) {
      return _hit('Cómo', 0.9);
    }

    // 3) COMER — mano en la boca, quieta
    if (s.handNearMouth && still) {
      return _hit('Comer', 0.8);
    }

    // 4) GRACIAS — mano cerca de la cara SIN vaivén
    if (face && !high && still) {
      return _hit('Gracias', 0.84);
    }

    // 5) POR FAVOR / DOLOR — las dos manos juntas frente al cuerpo, quietas
    if (s.handsTogether && !s.handLow && still) {
      return _hit(s.bothHandsMid ? 'Dolor' : 'Por favor', 0.8);
    }

    // 6) YO — índice/mano al centro del pecho, quieta
    if (s.handOnChest && still) {
      return _hit('Yo', 0.9);
    }

    // 7) NO — pecho + vaivén horizontal amplio (flecha ↔)
    if (s.handMid && wave >= 0.22 && peaks >= 1 && nod < wave) {
      return _hit('No', 0.9);
    }

    // 8) SÍ — pecho + movimiento vertical (flecha ↑↓), pulgar/puño
    if (s.handMid && nod >= 0.18 && wave < 0.16) {
      return _hit('Sí', 0.88);
    }
    if (s.thumbUp && nod >= 0.12) {
      return _hit('Sí', 0.85);
    }

    // 9) BIEN — pecho/hombro, palma al frente, QUIETA
    if (s.handMid && !face && still) {
      return _hit('Bien', 0.84);
    }

    // 10) MAL — mano baja junto a la cadera, quieta
    if (s.handLow && still) {
      return _hit('Mal', 0.8);
    }

    // 11) ADIÓS — media altura + vaivén (más bajo que Hola)
    if (s.handUp && !high && !face && wave >= 0.18 && peaks >= 1) {
      return _hit('Adiós', 0.8);
    }

    return null;
  }

  SignDetectionResult _hit(String phrase, double confidence) {
    return SignDetectionResult(
      phrase: phrase,
      confidence: confidence,
      handsVisible: true,
      status: 'seña',
    );
  }

  /// Cuenta cambios de dirección horizontales (vaivén real).
  int _wavePeaks() {
    if (_history.length < 4) return 0;
    final xs = _window().map((e) => e.activeHandX).toList();
    var peaks = 0;
    for (var i = 2; i < xs.length; i++) {
      final d1 = xs[i - 1] - xs[i - 2];
      final d2 = xs[i] - xs[i - 1];
      if (d1.abs() < 0.03 || d2.abs() < 0.03) continue;
      if (d1.sign != d2.sign) peaks++;
    }
    return peaks;
  }

  List<_HandPose> _window() {
    final start = max(0, _history.length - 8);
    return _history.sublist(start);
  }

  double _horizontalAmp() {
    if (_history.length < 2) return 0;
    final xs = _window().map((e) => e.activeHandX).toList();
    return xs.reduce(max) - xs.reduce(min);
  }

  double _verticalAmp() {
    if (_history.length < 2) return 0;
    final ys = _window().map((e) => e.activeHandY).toList();
    return ys.reduce(max) - ys.reduce(min);
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
    required this.frame,
  });

  bool get anyHandVisible => leftOk || rightOk;

  /// Mano de trabajo = la más levantada de las visibles.
  bool get _useLeft =>
      leftOk && (!rightOk || leftHandY <= rightHandY);
  double get activeHandX => _useLeft ? leftHandX : rightHandX;
  double get activeHandY => _useLeft ? leftHandY : rightHandY;
  double get activeSpread => _useLeft ? leftSpread : rightSpread;
  double get activeWristY => _useLeft ? leftWristY : rightWristY;
  double get activeThumbY => _useLeft ? leftThumbY : rightThumbY;

  /// Mano por encima de la cabeza (zona de saludo).
  bool get handAboveHead => activeHandY < noseY - 0.25;

  /// Mano a la altura de la cara: mejilla, barbilla, frente.
  bool get handInFaceZone =>
      (activeHandX - noseX).abs() < 0.85 &&
      activeHandY > noseY - 0.45 &&
      activeHandY < noseY + 0.70;

  bool get handNearMouth =>
      (activeHandX - noseX).abs() < 0.55 &&
      (activeHandY - mouthY).abs() < 0.28;

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
      activeHandY > hipY - 0.15 &&
      (activeHandX - shoulderCenterX).abs() < 0.40;

  /// Pulgar arriba con mano cerrada (Sí).
  bool get thumbUp =>
      activeThumbY < activeWristY - 0.18 && activeSpread < 0.42;

  static _HandPose? fromPose(
    Pose pose, {
    required double imageWidth,
    required double imageHeight,
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

    final leftOk = lw != null || li != null;
    final rightOk = rw != null || ri != null;

    final w = imageWidth <= 0 ? 1.0 : imageWidth;
    final h = imageHeight <= 0 ? 1.0 : imageHeight;

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

    final leftPalm = palm(lw, li, lp, lt);
    final rightPalm = palm(rw, ri, rp, rt);
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
      frame: frame,
    );
  }
}
