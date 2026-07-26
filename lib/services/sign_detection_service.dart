import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'dart:math';
import 'dart:ui';

/// Resultado de una detección LSB en tiempo real.
class SignDetectionResult {
  final String phrase;
  final double confidence;
  final bool handsVisible;

  const SignDetectionResult({
    required this.phrase,
    required this.confidence,
    required this.handsVisible,
  });
}

/// Detecta señas básicas LSB con pose (ML Kit ≈ MediaPipe Holistic del
/// proyecto GestureGuide / LenguajeSenas_Web).
///
/// Nota: un modelo Keras LSTM completo requiere convertir .keras → TFLite.
/// Esta versión reconoce gestos frecuentes en el dispositivo, sin servidor.
class SignDetectionService {
  PoseDetector? _detector;
  bool _busy = false;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastPhrase;
  final List<_PoseSample> _history = [];

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

  Future<SignDetectionResult?> processCameraImage(
    CameraImage image, {
    required InputImageRotation rotation,
  }) async {
    if (_detector == null || _busy) return null;
    _busy = true;
    try {
      final input = _toInputImage(image, rotation);
      if (input == null) return null;

      final poses = await _detector!.processImage(input);
      if (poses.isEmpty) {
        return const SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: false,
        );
      }

      final sample = _PoseSample.fromPose(poses.first);
      if (sample == null) {
        return const SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: false,
        );
      }

      _history.add(sample);
      if (_history.length > 12) _history.removeAt(0);

      final handsVisible = sample.leftHandUp ||
          sample.rightHandUp ||
          sample.wristsNearFace ||
          sample.handsTogether;

      final guess = _classify(sample);
      if (guess == null) {
        return SignDetectionResult(
          phrase: '',
          confidence: 0,
          handsVisible: handsVisible,
        );
      }

      final now = DateTime.now();
      if (guess.phrase == _lastPhrase &&
          now.difference(_lastEmit) < const Duration(milliseconds: 1600)) {
        return SignDetectionResult(
          phrase: '',
          confidence: guess.confidence,
          handsVisible: handsVisible,
        );
      }
      if (now.difference(_lastEmit) < const Duration(milliseconds: 700)) {
        return SignDetectionResult(
          phrase: '',
          confidence: guess.confidence,
          handsVisible: handsVisible,
        );
      }

      _lastPhrase = guess.phrase;
      _lastEmit = now;
      return SignDetectionResult(
        phrase: guess.phrase,
        confidence: guess.confidence,
        handsVisible: handsVisible,
      );
    } catch (e) {
      debugPrint('SignDetection: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  SignDetectionResult? _classify(_PoseSample s) {
    if (s.wristsNearFace && s.rightHandUp) {
      return const SignDetectionResult(
        phrase: 'Gracias',
        confidence: 0.78,
        handsVisible: true,
      );
    }

    if (_history.length >= 4) {
      final ys = _history.map((e) => e.rightWristY).toList();
      final amp = ys.reduce(max) - ys.reduce(min);
      if (amp > 0.08 && s.rightHandMid && !s.leftHandUp) {
        return const SignDetectionResult(
          phrase: 'Sí',
          confidence: 0.72,
          handsVisible: true,
        );
      }
    }

    if (_history.length >= 5) {
      final xs = _history.map((e) => e.rightWristX).toList();
      final amp = xs.reduce(max) - xs.reduce(min);
      if (amp > 0.12 && s.rightHandMid) {
        return const SignDetectionResult(
          phrase: 'No',
          confidence: 0.7,
          handsVisible: true,
        );
      }
    }

    if (s.rightHandUp || s.leftHandUp) {
      if (_history.length >= 5) {
        final xs = _history
            .map((e) => e.rightHandUp ? e.rightWristX : e.leftWristX)
            .toList();
        final amp = xs.reduce(max) - xs.reduce(min);
        if (amp > 0.1) {
          return const SignDetectionResult(
            phrase: 'Hola',
            confidence: 0.8,
            handsVisible: true,
          );
        }
      }
      return const SignDetectionResult(
        phrase: 'Disculpe',
        confidence: 0.55,
        handsVisible: true,
      );
    }

    if (s.handsTogether) {
      return const SignDetectionResult(
        phrase: 'Por favor',
        confidence: 0.75,
        handsVisible: true,
      );
    }

    if (s.bothHandsMid && s.handsApart) {
      return const SignDetectionResult(
        phrase: '¿Cómo estás?',
        confidence: 0.65,
        handsVisible: true,
      );
    }

    return null;
  }

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
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

  bool get leftHandUp => leftWristY < leftShoulderY - 0.05;
  bool get rightHandUp => rightWristY < rightShoulderY - 0.05;
  bool get leftHandMid =>
      leftWristY > leftShoulderY - 0.02 && leftWristY < leftShoulderY + 0.18;
  bool get rightHandMid =>
      rightWristY > rightShoulderY - 0.02 && rightWristY < rightShoulderY + 0.18;
  bool get bothHandsMid => leftHandMid && rightHandMid;
  bool get wristsNearFace =>
      (leftWristY - noseY).abs() < 0.12 || (rightWristY - noseY).abs() < 0.12;
  bool get handsTogether =>
      (leftWristX - rightWristX).abs() < 0.1 &&
      (leftWristY - rightWristY).abs() < 0.1;
  bool get handsApart => (leftWristX - rightWristX).abs() > 0.25;

  static _PoseSample? fromPose(Pose pose) {
    final lw = pose.landmarks[PoseLandmarkType.leftWrist];
    final rw = pose.landmarks[PoseLandmarkType.rightWrist];
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    if (lw == null || rw == null || nose == null || ls == null || rs == null) {
      return null;
    }
    return _PoseSample(
      leftWristX: lw.x,
      leftWristY: lw.y,
      rightWristX: rw.x,
      rightWristY: rw.y,
      noseY: nose.y,
      leftShoulderY: ls.y,
      rightShoulderY: rs.y,
    );
  }
}
