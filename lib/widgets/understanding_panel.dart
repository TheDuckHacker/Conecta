import 'package:flutter/material.dart';

import 'package:conecta_lsb/services/sign_detection_service.dart';
import 'package:conecta_lsb/services/sign_guide.dart';
import 'package:conecta_lsb/theme/app_theme.dart';

/// Panel "Entendimiento": muestra en vivo cómo el motor lee la seña —
/// tipo de movimiento, fps y las 3 señas con más evidencia.
class UnderstandingPanel extends StatelessWidget {
  final SignDetectionService sign;
  const UnderstandingPanel({super.key, required this.sign});

  static String motionLabel(MotionKind k) => switch (k) {
        MotionKind.none => 'Sin manos',
        MotionKind.hold => 'Mano quieta',
        MotionKind.waveX => 'Vaivén ↔',
        MotionKind.waveY => 'Arriba-abajo ↕',
        MotionKind.transition => 'Transición (se ignora)',
        MotionKind.moving => 'Moviéndose…',
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SignUnderstanding>(
      valueListenable: sign.understanding,
      builder: (context, u, _) {
        return Container(
          width: 220,
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: AppColors.callBg.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.insights_rounded,
                      color: AppColors.brandBright, size: 16),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Entendimiento',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '${u.fps.round()} fps',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${motionLabel(u.motion)} · ${u.speed.toStringAsFixed(1)} hombros/s',
                style: TextStyle(
                  color: u.motion == MotionKind.transition
                      ? Colors.amberAccent
                      : Colors.white,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              if (u.top.isEmpty)
                const Text(
                  'Sin evidencia todavía',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                )
              else
                for (final (name, v) in u.top) _bar(name, v),
              const SizedBox(height: 4),
              const Text(
                'Emite al pasar la línea y superar a la 2.ª',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(String name, double v) {
    final pct = (v * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              SignGuide.labelFor(name),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  Container(
                    height: 10,
                    width: c.maxWidth * v.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: v >= 0.55
                          ? AppColors.successBright
                          : AppColors.brandBright,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  // Umbral de emisión (0.55).
                  Positioned(
                    left: c.maxWidth * 0.55,
                    child: Container(width: 2, height: 10, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 30,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
