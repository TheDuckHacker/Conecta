import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Resultado de una detección LSB en tiempo real.
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

/// Detección LSB en tiempo real con ML Kit Pose (estilo MediaPipe).
class SignDetectionService {
  PoseDetector? _detector;
  bool _busy = false;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastPhrase;
  final List<_PoseSample> _history = [];
  int _frameSkip = 0;

  Future<void> start() async {
    _detector ??= PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );
  }

  Future<void> stop() async {
    await _detector?.close();
    _detector = null;
    _history.clear();
  }

  /// Procesa un frame de cámara. [camera] ayuda a calcular la rotación correcta.
  Future<SignDetectionResult?> processCameraImage(
    CameraImage image, {
    required CameraDescription camera,
  }) async {
    if (_detector == null || _busy) return null;

    // Saltar 1 de cada 2 frames para fluidez en tiempo real
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
        return const SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: false,
          bodyVisible: false,
          status: 'buscando',
        );
      }

      final sample = _PoseSample.fromPose(
        poses.first,
        imageWidth: image.width.toDouble(),
        imageHeight: image.height.toDouble(),
      );
      if (sample == null) {
        return const SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: false,
          bodyVisible: true,
          status: 'cuerpo',
        );
      }

      _history.add(sample);
      if (_history.length > 10) _history.removeAt(0);

      final handsVisible = sample.leftHandUp ||
          sample.rightHandUp ||
          sample.wristsNearFace ||
          sample.handsTogether ||
          sample.rightHandMid ||
          sample.leftHandMid;

      final guess = _classify(sample);
      if (guess == null) {
        return SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: handsVisible,
          bodyVisible: true,
          status: handsVisible ? 'manos' : 'cuerpo',
        );
      }

      final now = DateTime.now();
      // Cooldown corto para tiempo real
      if (guess.phrase == _lastPhrase &&
          now.difference(_lastEmit) < const Duration(milliseconds: 900)) {
        return SignDetectionResult(
          phrase: '',
          confidence: guess.confidence,
          handsVisible: true,
          bodyVisible: true,
          status: 'seña',
        );
      }
      if (now.difference(_lastEmit) < const Duration(milliseconds: 450)) {
        return SignDetectionResult(
          phrase: '',
          confidence: guess.confidence,
          handsVisible: true,
          bodyVisible: true,
          status: 'seña',
        );
      }

      _lastPhrase = guess.phrase;
      _lastEmit = now;
      return SignDetectionResult(
        phrase: guess.phrase,
        confidence: guess.confidence,
        handsVisible: true,
        bodyVisible: true,
        status: 'seña',
      );
    } catch (e) {
      debugPrint('SignDetection: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  InputImageRotation _rotationForCamera(CameraDescription camera) {
    // Orientación del sensor (90/270 típico en móviles)
    final sensor = camera.sensorOrientation;
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensor) ??
          InputImageRotation.rotation0deg;
    }
    // Android front camera often mirrored; use sensor orientation directly
    return InputImageRotationValue.fromRawValue(sensor) ??
        InputImageRotation.rotation90deg;
  }

  SignDetectionResult? _classify(_PoseSample s) {
    // Gracias: mano cerca de la cara
    if (s.wristsNearFace) {
      return const SignDetectionResult(
        phrase: 'Gracias',
        confidence: 0.78,
        handsVisible: true,
        status: 'seña',
      );
    }

    // Sí: movimiento vertical de muñeca
    if (_history.length >= 3) {
      final ys = _history.map((e) => e.rightWristY).toList();
      final amp = ys.reduce(max) - ys.reduce(min);
      if (amp > 0.06 && s.rightHandMid && !s.leftHandUp) {
        return const SignDetectionResult(
          phrase: 'Sí',
          confidence: 0.72,
          handsVisible: true,
          status: 'seña',
        );
      }
    }

    // No: movimiento horizontal
    if (_history.length >= 4) {
      final xs = _history.map((e) => e.rightWristX).toList();
      final amp = xs.reduce(max) - xs.reduce(min);
      if (amp > 0.1 && (s.rightHandMid || s.rightHandUp)) {
        return const SignDetectionResult(
          phrase: 'No',
          confidence: 0.7,
          handsVisible: true,
          status: 'seña',
        );
      }
    }

    // Hola: mano arriba + oscilación
    if (s.rightHandUp || s.leftHandUp) {
      if (_history.length >= 4) {
        final xs = _history
            .map((e) => e.rightHandUp ? e.rightWristX : e.leftWristX)
            .toList();
        final amp = xs.reduce(max) - xs.reduce(min);
        if (amp > 0.08) {
          return const SignDetectionResult(
            phrase: 'Hola',
            confidence: 0.82,
            handsVisible: true,
            status: 'seña',
          );
        }
      }
      // Mano alzada estable
      return const SignDetectionResult(
        phrase: 'Hola',
        confidence: 0.6,
        handsVisible: true,
        status: 'seña',
      );
    }

    if (s.handsTogether) {
      return const SignDetectionResult(
        phrase: 'Por favor',
        confidence: 0.75,
        handsVisible: true,
        status: 'seña',
      );
    }

    if (s.bothHandsMid && s.handsApart) {
      return const SignDetectionResult(
        phrase: '¿Cómo estás?',
        confidence: 0.65,
        handsVisible: true,
        status: 'seña',
      );
    }

    return null;
  }

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
    try {
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          (Platform.isAndroid
              ? InputImageFormat.nv21
              : InputImageFormat.bgra8888);

      Uint8List bytes;
      int bytesPerRow;

      if (Platform.isAndroid) {
        // NV21: preferir plano Y+UV concatenado correctamente
        if (image.planes.length == 1) {
          bytes = image.planes.first.bytes;
          bytesPerRow = image.planes.first.bytesPerRow;
        } else {
          // Concatenar planos (Y + VU)
          final y = image.planes[0].bytes;
          final uv = image.planes.length > 1
              ? image.planes[1].bytes
              : Uint8List(0);
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

class _PoseSample {
  final double leftWristX;
  final double leftWristY;
  final double rightWristX;
  final double rightWristY;
  final double noseY;
  final double leftShoulderY;
  final double rightShoulderY;

  const _PoseSample({
    required this.leftWristX,
    required this.leftWristY,
    required this.rightWristX,
    required this.rightWristY,
    required this.noseY,
    required this.leftShoulderY,
    required this.rightShoulderY,
  });

  bool get leftHandUp => leftWristY < leftShoulderY - 0.04;
  bool get rightHandUp => rightWristY < rightShoulderY - 0.04;
  bool get leftHandMid =>
      leftWristY > leftShoulderY - 0.03 && leftWristY < leftShoulderY + 0.22;
  bool get rightHandMid =>
      rightWristY > rightShoulderY - 0.03 && rightWristY < rightShoulderY + 0.22;
  bool get bothHandsMid => leftHandMid && rightHandMid;
  bool get wristsNearFace =>
      (leftWristY - noseY).abs() < 0.1 || (rightWristY - noseY).abs() < 0.1;
  bool get handsTogether =>
      (leftWristX - rightWristX).abs() < 0.12 &&
      (leftWristY - rightWristY).abs() < 0.12;
  bool get handsApart => (leftWristX - rightWristX).abs() > 0.22;

  static _PoseSample? fromPose(
    Pose pose, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final lw = pose.landmarks[PoseLandmarkType.leftWrist];
    final rw = pose.landmarks[PoseLandmarkType.rightWrist];
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    if (lw == null || rw == null || nose == null || ls == null || rs == null) {
      return null;
    }

    // ML Kit entrega píxeles: normalizar a 0–1
    final w = imageWidth <= 0 ? 1.0 : imageWidth;
    final h = imageHeight <= 0 ? 1.0 : imageHeight;

    bool ok(PoseLandmark p) => p.likelihood > 0.3;

    // Si las muñecas no son confiables, igual intentar con hombros
    if (!ok(ls) || !ok(rs) || !ok(nose)) return null;

    return _PoseSample(
      leftWristX: lw.x / w,
      leftWristY: lw.y / h,
      rightWristX: rw.x / w,
      rightWristY: rw.y / h,
      noseY: nose.y / h,
      leftShoulderY: ls.y / h,
      rightShoulderY: rs.y / h,
    );
  }
}
