import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'package:conecta_lsb/services/sign_detection_service.dart';

/// Dibuja los puntos de las manos (muñeca, pulgar, índice, meñique) y los
/// brazos sobre la vista de cámara, igual que la guía visual.
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
      ..color = const Color(0xff27C7D9).withValues(alpha: 0.75)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (final b in HandPointsFrame.bones) {
      final a = mapped[b[0]];
      final c = mapped[b[1]];
      if (a == null || c == null) continue;
      canvas.drawLine(a, c, bone);
    }

    final handDot = Paint()..color = const Color(0xff2ECC71);
    final bodyDot = Paint()..color = Colors.white.withValues(alpha: 0.7);
    final halo = Paint()
      ..color = const Color(0xff2ECC71).withValues(alpha: 0.25);

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

  @override
  bool shouldRepaint(_HandPointsPainter old) =>
      old.frame != frame || old.mirror != mirror;
}
