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

/// Detección estilo [GestureGuide](https://github.com/Innominados/LenguajeSenas_Web):
/// 1. Mientras hay manos → acumular frames de la seña
/// 2. Confirmar seña estable
/// 3. Emitir UNA frase
/// 4. Limpiar buffer → listo para la siguiente seña
class SignDetectionService {
  PoseDetector? _detector;
  bool _busy = false;
  final List<_HandPose> _history = [];
  int _frameSkip = 0;

  /// Votos de la seña actual.
  final Map<String, int> _votes = {};
  int _gestureFrames = 0;
  String? _lastEmitted;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  static const int _minGestureFrames = 3;
  static const int _votesToConfirm = 3;

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

    _frameSkip = (_frameSkip + 1) % 2;
    if (_frameSkip != 0) return null;

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
        return const SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: false,
          status: 'buscando',
        );
      }

      final sample = _HandPose.fromPose(
        poses.first,
        imageWidth: image.width.toDouble(),
        imageHeight: image.height.toDouble(),
      );

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
      if (_history.length > 12) _history.removeAt(0);
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
    // Misma seña: cooldown más largo para no repetir "Hola Hola Hola"
    final same = phrase == _lastEmitted;
    final wait = same
        ? const Duration(milliseconds: 2200)
        : const Duration(milliseconds: 500);
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

  /// Clasifica según la guía visual `assets/msl/guia_senas.png`.
  SignDetectionResult? _classify(_HandPose s) {
    if (_history.length < 3) return null;

    final wave = _horizontalAmp();
    final nod = _verticalAmp();
    final peaks = _wavePeaks();
    final handUp = s.rightHandUp || s.leftHandUp;
    final handHigh = s.rightHandHigh || s.leftHandHigh;
    final mid = s.rightHandMid || s.leftHandMid;

    // 1) YO — panel: índice al pecho, quieto
    if (s.handOnChest && wave < 0.04 && nod < 0.04) {
      return _hit('Yo', 0.88);
    }

    // 2) ¿CÓMO ESTÁS? — panel: cerca de barbilla + vaivén corto
    if (s.wristsNearFace && !handHigh && wave >= 0.028 && wave < 0.12) {
      return _hit('Cómo', 0.86);
    }

    // 3) Gracias — cerca de cara SIN vaivén (después de Cómo)
    if (s.wristsNearFace && wave < 0.028 && !handHigh) {
      return _hit('Gracias', 0.84);
    }

    // 4) Comer — boca
    if (s.wristsNearMouth && wave < 0.035 && nod < 0.04) {
      return _hit('Comer', 0.8);
    }

    // 5) Por favor / Dolor — manos juntas
    if (s.leftOk && s.rightOk && s.handsTogether) {
      if (s.bothHandsMid) return _hit('Dolor', 0.8);
      return _hit('Por favor', 0.8);
    }

    // 6) NO — panel: pecho + vaivén horizontal (flecha ↔)
    if (mid && !handHigh && wave >= 0.07 && peaks >= 1 && nod < wave) {
      return _hit('No', 0.88);
    }

    // 7) SÍ — panel: pecho + movimiento vertical (flecha ↑↓)
    if (mid && !handHigh && nod >= 0.045 && wave < 0.05) {
      return _hit('Sí', 0.86);
    }

    // 8) BIEN — panel: pecho, palma al frente, QUIETO
    if (mid &&
        !handHigh &&
        wave < 0.03 &&
        nod < 0.03 &&
        !s.wristsNearFace) {
      return _hit('Bien', 0.82);
    }

    // 9) Mal — mano baja
    if (s.handLowDominant && wave < 0.045 && nod < 0.045) {
      return _hit('Mal', 0.8);
    }

    // 10) Adiós — media altura + vaivén (no tan alto como Hola)
    if (handUp && !handHigh && wave >= 0.055 && peaks >= 1) {
      return _hit('Adiós', 0.8);
    }

    // 11) HOLA — panel: mano BIEN ARRIBA + vaivén lado a lado
    if (handHigh && wave >= 0.05 && peaks >= 1) {
      return _hit('Hola', 0.93);
    }
    if (handHigh && _history.length >= 5 && wave >= 0.035) {
      return _hit('Hola', 0.8);
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
    final start = max(0, _history.length - 10);
    final xs = _history.sublist(start).map((e) => e.activeWristX).toList();
    var peaks = 0;
    for (var i = 2; i < xs.length; i++) {
      final d1 = xs[i - 1] - xs[i - 2];
      final d2 = xs[i] - xs[i - 1];
      if (d1.abs() < 0.008 || d2.abs() < 0.008) continue;
      if (d1.sign != d2.sign) peaks++;
    }
    return peaks;
  }

  double _horizontalAmp() {
    if (_history.length < 3) return 0;
    final start = max(0, _history.length - 8);
    final xs = _history.sublist(start).map((e) => e.activeWristX).toList();
    return xs.reduce(max) - xs.reduce(min);
  }

  double _verticalAmp() {
    if (_history.length < 3) return 0;
    final start = max(0, _history.length - 8);
    final ys = _history.sublist(start).map((e) => e.activeWristY).toList();
    return ys.reduce(max) - ys.reduce(min);
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

class _HandPose {
  final double leftWristX;
  final double leftWristY;
  final double rightWristX;
  final double rightWristY;
  final double noseY;
  final double leftShoulderY;
  final double rightShoulderY;
  final double leftHipY;
  final double rightHipY;
  final bool leftOk;
  final bool rightOk;

  const _HandPose({
    required this.leftWristX,
    required this.leftWristY,
    required this.rightWristX,
    required this.rightWristY,
    required this.noseY,
    required this.leftShoulderY,
    required this.rightShoulderY,
    required this.leftHipY,
    required this.rightHipY,
    required this.leftOk,
    required this.rightOk,
  });

  bool get anyHandVisible => leftOk || rightOk;
  /// Mano claramente por encima del hombro (saludo).
  bool get leftHandHigh => leftOk && leftWristY < leftShoulderY - 0.10;
  bool get rightHandHigh => rightOk && rightWristY < rightShoulderY - 0.10;
  bool get leftHandUp => leftOk && leftWristY < leftShoulderY - 0.04;
  bool get rightHandUp => rightOk && rightWristY < rightShoulderY - 0.04;
  bool get leftHandMid =>
      leftOk &&
      leftWristY > leftShoulderY - 0.02 &&
      leftWristY < leftShoulderY + 0.22;
  bool get rightHandMid =>
      rightOk &&
      rightWristY > rightShoulderY - 0.02 &&
      rightWristY < rightShoulderY + 0.22;
  bool get bothHandsMid => leftHandMid && rightHandMid;
  bool get wristsNearFace =>
      (leftOk &&
          (leftWristY - noseY).abs() < 0.12 &&
          leftWristY < leftShoulderY + 0.02) ||
      (rightOk &&
          (rightWristY - noseY).abs() < 0.12 &&
          rightWristY < rightShoulderY + 0.02);
  bool get wristsNearMouth =>
      (leftOk &&
          leftWristY > noseY - 0.02 &&
          leftWristY < leftShoulderY + 0.05 &&
          (leftWristY - noseY).abs() < 0.14) ||
      (rightOk &&
          rightWristY > noseY - 0.02 &&
          rightWristY < rightShoulderY + 0.05 &&
          (rightWristY - noseY).abs() < 0.14);
  bool get handsTogether =>
      leftOk &&
      rightOk &&
      (leftWristX - rightWristX).abs() < 0.14 &&
      (leftWristY - rightWristY).abs() < 0.14;
  bool get handOnChest =>
      (rightOk &&
          rightWristY > rightShoulderY + 0.02 &&
          rightWristY < rightHipY - 0.08 &&
          rightWristX > 0.32 &&
          rightWristX < 0.68) ||
      (leftOk &&
          leftWristY > leftShoulderY + 0.02 &&
          leftWristY < leftHipY - 0.08 &&
          leftWristX > 0.32 &&
          leftWristX < 0.68);
  bool get handLowDominant =>
      (rightOk && rightWristY > rightHipY - 0.01) ||
      (leftOk && leftWristY > leftHipY - 0.01);

  double get activeWristX => rightOk ? rightWristX : leftWristX;
  double get activeWristY => rightOk ? rightWristY : leftWristY;

  static _HandPose? fromPose(
    Pose pose, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final lw = pose.landmarks[PoseLandmarkType.leftWrist];
    final rw = pose.landmarks[PoseLandmarkType.rightWrist];
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    final lh = pose.landmarks[PoseLandmarkType.leftHip];
    final rh = pose.landmarks[PoseLandmarkType.rightHip];

    if (nose == null || ls == null || rs == null) return null;

    final w = imageWidth <= 0 ? 1.0 : imageWidth;
    final h = imageHeight <= 0 ? 1.0 : imageHeight;
    bool ok(PoseLandmark? p) => p != null && p.likelihood > 0.15;

    final leftOk = ok(lw);
    final rightOk = ok(rw);
    if (!leftOk && !rightOk) return null;

    return _HandPose(
      leftWristX: (lw?.x ?? 0) / w,
      leftWristY: (lw?.y ?? 0) / h,
      rightWristX: (rw?.x ?? 0) / w,
      rightWristY: (rw?.y ?? 0) / h,
      noseY: nose.y / h,
      leftShoulderY: ls.y / h,
      rightShoulderY: rs.y / h,
      leftHipY: (lh?.y ?? ls.y + 0.35 * h) / h,
      rightHipY: (rh?.y ?? rs.y + 0.35 * h) / h,
      leftOk: leftOk,
      rightOk: rightOk,
    );
  }
}
