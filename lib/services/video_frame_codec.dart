import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Convierte un [CameraImage] a JPEG pequeño para enviarlo al otro usuario.
class VideoFrameCodec {
  VideoFrameCodec._();

  /// Ancho máximo del frame (altura se escala). Más bajo = más fluido en red.
  static const int maxWidth = 240;
  static const int jpegQuality = 55;

  /// Corre en isolate para no congelar la UI.
  static Future<Uint8List?> encodeJpeg(CameraImage image) {
    return compute(_encodeIsolate, _EncodeArgs(
      width: image.width,
      height: image.height,
      format: image.format.group,
      planes: image.planes
          .map(
            (p) => _PlaneData(
              bytes: Uint8List.fromList(p.bytes),
              bytesPerRow: p.bytesPerRow,
              bytesPerPixel: p.bytesPerPixel ?? 1,
            ),
          )
          .toList(),
    ));
  }

  static Uint8List? _encodeIsolate(_EncodeArgs args) {
    try {
      final rgb = _toRgb(args);
      if (rgb == null) return null;
      final w = rgb.width;
      final h = rgb.height;
      img.Image out = rgb;
      if (w > maxWidth) {
        final nh = (h * maxWidth / w).round();
        out = img.copyResize(rgb, width: maxWidth, height: nh);
      }
      return Uint8List.fromList(
        img.encodeJpg(out, quality: jpegQuality),
      );
    } catch (e) {
      // ignore: avoid_print
    }
    return null;
  }

  static img.Image? _toRgb(_EncodeArgs args) {
    final w = args.width;
    final h = args.height;
    if (args.planes.isEmpty) return null;

    // iOS / algunos Android: BGRA8888 en un solo plano
    if (args.format == ImageFormatGroup.bgra8888 ||
        (args.planes.length == 1 && (args.planes.first.bytesPerPixel >= 4))) {
      final p = args.planes.first;
      final out = img.Image(width: w, height: h);
      final rowStride = p.bytesPerRow;
      final bpp = p.bytesPerPixel.clamp(4, 4);
      for (var y = 0; y < h; y++) {
        final row = y * rowStride;
        for (var x = 0; x < w; x++) {
          final i = row + x * bpp;
          if (i + 2 >= p.bytes.length) continue;
          final b = p.bytes[i];
          final g = p.bytes[i + 1];
          final r = p.bytes[i + 2];
          out.setPixelRgb(x, y, r, g, b);
        }
      }
      return out;
    }

    // Android típico: NV21 (Y + intercalado VU) en 1 o 2 planos
    final yPlane = args.planes[0];
    Uint8List uvBytes;
    int uvRowStride;
    if (args.planes.length >= 2) {
      uvBytes = args.planes[1].bytes;
      uvRowStride = args.planes[1].bytesPerRow;
    } else {
      // Todo en un buffer: Y luego VU
      final ySize = w * h;
      if (yPlane.bytes.length < ySize + w) return null;
      uvBytes = yPlane.bytes.sublist(ySize);
      uvRowStride = w;
    }

    final out = img.Image(width: w, height: h);
    final yRow = yPlane.bytesPerRow;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final yp = yPlane.bytes[y * yRow + x] & 0xff;
        final uvIndex = (y >> 1) * uvRowStride + (x & ~1);
        if (uvIndex + 1 >= uvBytes.length) {
          out.setPixelRgb(x, y, yp, yp, yp);
          continue;
        }
        final v = (uvBytes[uvIndex] & 0xff) - 128;
        final u = (uvBytes[uvIndex + 1] & 0xff) - 128;
        final r = (yp + 1.370705 * v).round().clamp(0, 255);
        final g = (yp - 0.337633 * u - 0.698001 * v).round().clamp(0, 255);
        final b = (yp + 1.732446 * u).round().clamp(0, 255);
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }
}

class _PlaneData {
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
  const _PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });
}

class _EncodeArgs {
  final int width;
  final int height;
  final ImageFormatGroup format;
  final List<_PlaneData> planes;
  const _EncodeArgs({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
  });
}
