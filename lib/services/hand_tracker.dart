import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart'
    show CameraImageData, CameraImageFormat, CameraImagePlane;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;
import 'package:hand_landmarker/hand_landmarker.dart';

/// Forma de una mano a partir de los 21 puntos de MediaPipe Hand Landmarker.
///
/// Índices MediaPipe: 0 muñeca · 1-4 pulgar · 5-8 índice · 9-12 medio ·
/// 13-16 anular · 17-20 meñique (MCP, PIP, DIP, punta).
/// Coordenadas normalizadas (0..1) sobre la imagen ya rotada, igual que
/// ML Kit Pose, así ambos modelos comparten sistema de coordenadas.
class HandShape {
  final List<Offset> points;

  HandShape(this.points);

  Offset get wrist => points[0];

  /// Centro de la palma (muñeca + nudillos).
  Offset get palm {
    const ids = [0, 5, 9, 13, 17];
    var x = 0.0;
    var y = 0.0;
    for (final i in ids) {
      x += points[i].dx;
      y += points[i].dy;
    }
    return Offset(x / ids.length, y / ids.length);
  }

  double _d(int a, int b) => (points[a] - points[b]).distance;

  /// Dedo estirado: la punta está claramente más lejos de la muñeca que la
  /// articulación media (invariante a rotación y distancia).
  bool _extended(int pip, int tip) => _d(tip, 0) > _d(pip, 0) * 1.12;

  bool get indexExtended => _extended(6, 8);
  bool get middleExtended => _extended(10, 12);
  bool get ringExtended => _extended(14, 16);
  bool get pinkyExtended => _extended(18, 20);

  /// Pulgar separado de la palma (punta lejos del nudillo del índice).
  bool get thumbExtended => _d(4, 5) > _d(3, 5) * 1.15 && _d(4, 9) > _d(2, 9);

  int get extendedFingers => [
        indexExtended,
        middleExtended,
        ringExtended,
        pinkyExtended,
      ].where((e) => e).length;

  /// Mano abierta / plana (Hola, Bien, No).
  bool get isOpen => extendedFingers >= 4;

  /// Puño: ningún dedo largo estirado.
  bool get isFist => extendedFingers == 0;

  /// Solo el índice estirado (Yo: apuntar al pecho).
  bool get indexOnly =>
      indexExtended && !middleExtended && !ringExtended && !pinkyExtended;

  /// Pulgar arriba: puño con el pulgar por encima de todos los nudillos (Sí).
  bool get thumbUp {
    if (extendedFingers > 1 || !thumbExtended) return false;
    final knuckleTop = [5, 9, 13, 17].map((i) => points[i].dy).reduce(min);
    return points[4].dy < knuckleTop - _d(5, 17) * 0.6;
  }
}

/// Envoltorio de MediaPipe Hand Landmarker (21 puntos por mano, CPU).
///
/// Solo Android. Si el plugin no carga, [available] queda en false y
/// [SignDetectionService] sigue con los puntos de mano de ML Kit Pose.
class HandTracker {
  HandLandmarkerPlugin? _plugin;
  StreamSubscription<List<Hand>>? _sub;
  List<HandShape> _hands = const [];
  DateTime _handsAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFeed = DateTime.fromMillisecondsSinceEpoch(0);

  bool get available => _plugin != null;

  /// Manos del último resultado, si es reciente (< 350 ms).
  List<HandShape> get hands =>
      DateTime.now().difference(_handsAt) < const Duration(milliseconds: 350)
          ? _hands
          : const [];

  Future<void> start() async {
    if (_plugin != null || !Platform.isAndroid) return;
    // CPU: el delegado GPU de TFLite falla en emuladores y en algunos GPU
    // (GL_INVALID_ENUM en cada frame, error nativo que no llega a Dart).
    // El modelo de manos es liviano: en CPU va a ~20 fps en un celular medio.
    try {
      _plugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.cpu,
      );
    } catch (e) {
      debugPrint('HandTracker no disponible: $e');
      _plugin = null;
      return;
    }
    _sub = _plugin!.landmarkStream.listen(
      (hands) {
        _hands = hands
            .where((h) => h.landmarks.length == 21)
            .map((h) => HandShape(
                  h.landmarks.map((l) => Offset(l.x, l.y)).toList(),
                ))
            .toList();
        _handsAt = DateTime.now();
      },
      onError: (Object e) => debugPrint('HandTracker stream: $e'),
    );
  }

  /// Envía el frame a MediaPipe (asíncrono, no bloquea). Máx. ~20 fps.
  void feed(CameraImage image, int sensorOrientation) {
    final plugin = _plugin;
    if (plugin == null) return;
    final now = DateTime.now();
    if (now.difference(_lastFeed) < const Duration(milliseconds: 50)) return;
    _lastFeed = now;
    try {
      final yuv = image.planes.length >= 3 ? image : _nv21AsYuv420(image);
      if (yuv == null) return;
      plugin.processFrame(yuv, sensorOrientation);
    } catch (e) {
      debugPrint('HandTracker feed: $e');
    }
  }

  /// El plugin pide 3 planos (Y, U, V). La cámara del proyecto entrega NV21
  /// (Y + VU intercalado) para ML Kit: se exponen U y V como vistas del
  /// mismo buffer con pixelStride 2, sin copiar.
  CameraImage? _nv21AsYuv420(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final ySize = w * h;
    final Uint8List y;
    final Uint8List vu;
    final int yRow;
    final int vuRow;
    if (image.planes.length == 1) {
      final all = image.planes.first.bytes;
      if (all.length < ySize + ySize ~/ 2) return null;
      yRow = image.planes.first.bytesPerRow;
      y = Uint8List.sublistView(all, 0, ySize);
      vu = Uint8List.sublistView(all, ySize);
      vuRow = w;
    } else {
      y = image.planes[0].bytes;
      yRow = image.planes[0].bytesPerRow;
      vu = image.planes[1].bytes;
      vuRow = image.planes[1].bytesPerRow;
    }
    if (vu.length < 2) return null;
    return CameraImage.fromPlatformInterface(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
        width: w,
        height: h,
        planes: [
          CameraImagePlane(bytes: y, bytesPerRow: yRow, bytesPerPixel: 1),
          CameraImagePlane(
            bytes: Uint8List.sublistView(vu, 1),
            bytesPerRow: vuRow,
            bytesPerPixel: 2,
          ),
          CameraImagePlane(bytes: vu, bytesPerRow: vuRow, bytesPerPixel: 2),
        ],
      ),
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      _plugin?.dispose();
    } catch (_) {}
    _plugin = null;
    _hands = const [];
  }
}
