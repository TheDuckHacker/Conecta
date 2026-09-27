import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:conecta_lsb/theme/app_theme.dart';

import 'package:conecta_lsb/services/sign_detection_service.dart';

/// Dibuja los puntos de las manos sobre la vista de cámara: esqueleto de
/// dedos (MediaPipe, 21 puntos) o, si no está, muñeca/pulgar/índice/meñique
/// de ML Kit Pose, igual que la guía visual.
class HandPointsOverlay extends StatelessWidget {
  final ValueListenable<HandPointsFrame?> frames;

  /// La cámara frontal se muestra espejada: los puntos también.
  final bool mirror;

  const HandPointsOverlay({
    super.key,
    required this.frames,
    this.mirror = true,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<HandPointsFrame?>(
        valueListenable: frames,
        builder: (context, frame, _) {
          if (frame == null) return const SizedBox.expand();
          return CustomPaint(
            painter: _HandPointsPainter(frame: frame, mirror: mirror),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _HandPointsPainter extends CustomPainter {
  final HandPointsFrame frame;
  final bool mirror;

  _HandPointsPainter({required this.frame, required this.mirror});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // La cámara se muestra con BoxFit.cover: replicamos ese encuadre.
    final aspect = frame.aspect <= 0 ? 0.75 : frame.aspect;
    final drawW = size.width > size.height * aspect
        ? size.width
        : size.height * aspect;
    final drawH = drawW / aspect;
    final dx = (size.width - drawW) / 2;
    final dy = (size.height - drawH) / 2;

    Offset? map(Offset? p) {
      if (p == null) return null;
      final x = mirror ? 1 - p.dx : p.dx;
      return Offset(dx + x * drawW, dy + p.dy * drawH);
    }

    final mapped = frame.points.map(map).toList();

    final bone = Paint()
      ..color = AppColors.brandBright.withValues(alpha: 0.75)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Con MediaPipe: brazos de ML Kit + esqueleto completo de los dedos.
    if (frame.hands.isNotEmpty) {
      _paintWithFingers(canvas, mapped, map, bone);
      return;
    }

    for (final b in HandPointsFrame.bones) {
      final a = mapped[b[0]];
      final c = mapped[b[1]];
      if (a == null || c == null) continue;
      canvas.drawLine(a, c, bone);
    }

    final handDot = Paint()..color = AppColors.successBright;
    final bodyDot = Paint()..color = Colors.white.withValues(alpha: 0.7);
    final halo = Paint()
      ..color = AppColors.successBright.withValues(alpha: 0.25);

    for (var i = 0; i < mapped.length; i++) {
      final p = mapped[i];
      if (p == null) continue;
      final isHand = HandPointsFrame.handIndexes.contains(i);
      if (isHand) {
        canvas.drawCircle(p, 11, halo);
        canvas.drawCircle(p, 5, handDot);
      } else {
        canvas.drawCircle(p, 4, bodyDot);
      }
    }
  }

  void _paintWithFingers(
    Canvas canvas,
    List<Offset?> body,
    Offset? Function(Offset?) map,
    Paint bone,
  ) {
    for (final b in HandPointsFrame.armBones) {
      final a = body[b[0]];
      final c = body[b[1]];
      if (a == null || c == null) continue;
      canvas.drawLine(a, c, bone);
    }
    final bodyDot = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (final i in const [0, 1, 6, 7]) {
      final p = body[i];
      if (p != null) canvas.drawCircle(p, 4, bodyDot);
    }

    final finger = Paint()
      ..color = AppColors.successBright
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final joint = Paint()..color = Colors.white;
    final tip = Paint()..color = AppColors.successBright;

    for (final hand in frame.hands) {
      final pts = hand.map(map).toList();
      for (final b in HandPointsFrame.fingerBones) {
        final a = pts[b[0]];
        final c = pts[b[1]];
        if (a == null || c == null) continue;
        canvas.drawLine(a, c, finger);
      }
      for (var i = 0; i < pts.length; i++) {
        final p = pts[i];
        if (p == null) continue;
        final isTip = i == 4 || i == 8 || i == 12 || i == 16 || i == 20;
        canvas.drawCircle(p, isTip ? 5 : 3, isTip ? tip : joint);
      }
    }
  }

  @override
  bool shouldRepaint(_HandPointsPainter old) =>
      old.frame != frame || old.mirror != mirror;
}
