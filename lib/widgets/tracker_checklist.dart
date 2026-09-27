import 'package:flutter/material.dart';

import 'package:conecta_lsb/services/sign_detection_service.dart';
import 'package:conecta_lsb/theme/app_theme.dart';

/// Calibración en vivo del tracker: cuerpo · manos · luz (verde = OK).
/// Se usa en la videollamada (modo sordo) y en Traducción.
class TrackerChecklist extends StatelessWidget {
  final SignDetectionService sign;

  /// Manos según ML Kit, para cuando MediaPipe no está disponible.
  final bool handsVisible;

  const TrackerChecklist({
    super.key,
    required this.sign,
    required this.handsVisible,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TrackerDiagnostics>(
      valueListenable: sign.diagnostics,
      builder: (context, d, _) {
        final bodyLabel = d.body
            ? 'Cuerpo'
            : (d.bodyFromMemory ? 'Cuerpo (memoria)' : 'Sin hombros');
        final handsOk = d.fingerTracking ? d.hands > 0 : handsVisible;
        final handsLabel = !d.fingerTracking
            ? (handsVisible ? 'Manos' : 'Sin manos')
            : switch (d.hands) {
                0 => 'Sin manos',
                1 => '1 mano · dedos',
                _ => '2 manos · dedos',
              };
        final lightLabel =
            d.luma < 0 ? 'Luz…' : (d.lowLight ? 'Poca luz' : 'Luz');
        return Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            _Check(bodyLabel, d.bodyOk, Icons.accessibility_new_rounded),
            _Check(handsLabel, handsOk, Icons.back_hand_outlined),
            _Check(lightLabel, !d.lowLight, Icons.light_mode_outlined),
          ],
        );
      },
    );
  }
}

class _Check extends StatelessWidget {
  final String label;
  final bool ok;
  final IconData icon;
  const _Check(this.label, this.ok, this.icon);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: ${ok ? 'bien' : 'revisar'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm + 2,
          vertical: AppSpace.xs + 1,
        ),
        decoration: BoxDecoration(
          color:
              ok ? AppColors.success : AppColors.callBg.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: ok ? null : Border.all(color: Colors.white38),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ok ? Icons.check_rounded : icon,
                color: Colors.white, size: 15),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
