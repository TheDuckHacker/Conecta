import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Vista de cámara sin aplastar (cubre pantalla manteniendo proporción).
class CameraCoverPreview extends StatelessWidget {
  final CameraController controller;
  final bool mirror;

  const CameraCoverPreview({
    super.key,
    required this.controller,
    this.mirror = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const ColoredBox(color: Color(0xff0F172A));
    }

    final preview = controller.value.previewSize;
    // previewSize viene en landscape (ancho > alto) aunque el teléfono esté
    // en vertical: intercambiamos para el layout portrait.
    final previewW = preview?.height ?? 720.0;
    final previewH = preview?.width ?? 1280.0;

    Widget child = CameraPreview(controller);
    if (mirror &&
        controller.description.lensDirection == CameraLensDirection.front) {
      child = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
        child: child,
      );
    }

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewW,
            height: previewH,
            child: child,
          ),
        ),
      ),
    );
  }
}
