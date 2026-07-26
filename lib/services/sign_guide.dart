import 'package:flutter/material.dart';

/// Fuente única: textos = misma guía visual `assets/msl/guia_senas.png`
/// (Academia, Traducción, videollamada y detección).
class SignGuide {
  static const asset = 'assets/msl/guia_senas.png';

  /// Pasos que coinciden con cada panel de la imagen.
  static const Map<String, List<String>> steps = {
    'Hola': [
      'Como en la guía (panel HOLA): mano abierta a la altura de los ojos o más arriba, junto a la cabeza.',
      'Palma al frente, dedos abiertos.',
      'Muévela de LADO a LADO AMPLIO (flecha horizontal) 1 segundo.',
    ],
    'Cómo': [
      'Como en la guía (panel ¿CÓMO ESTÁS?): mano cerca de la barbilla / mejilla.',
      'Dedos juntos, un poco curvados hacia la cara.',
      'Movimiento CORTO de lado a lado (flecha pequeña, mucho menos que Hola).',
      'La app lo convierte en la frase: ¿Cómo estás?',
    ],
    'Yo': [
      'Como en la guía (panel YO): apunta al pecho con el índice.',
      'Mantén la mano en el pecho, quieta 1–2 segundos.',
    ],
    'Bien': [
      'Como en la guía (panel BIEN): mano a la altura del pecho/hombro.',
      'Palma al frente, dedos juntos (como “stop”).',
      'Sin mover: quieta 1–2 segundos.',
    ],
    'Sí': [
      'Como en la guía (panel SÍ): mano a la altura del pecho.',
      'Pulgar hacia arriba (o puño) y muévela ARRIBA y ABAJO.',
    ],
    'No': [
      'Como en la guía (panel NO): mano plana a la altura del pecho.',
      'Muévela de LADO a LADO cruzando el pecho (flecha horizontal).',
    ],
    'Gracias': [
      'Mano cerca de la barbilla, quieta 1–2 segundos (sin vaivén fuerte).',
    ],
    'Por favor': [
      'Junta las dos manos frente al cuerpo y manténlas quietas.',
    ],
    'Adiós': [
      'Mano a media altura (más baja que Hola) y vaivén suave de lado a lado.',
    ],
    'Mal': [
      'Baja la mano hacia la cadera y mantenla quieta.',
    ],
    'Dolor': [
      'Junta las dos manos a la altura del pecho.',
    ],
    'Comer': [
      'Mano cerca de la boca, quieta 1–2 segundos.',
    ],
    'Beber': [
      'Mano cerca de la boca (como vaso), quieta 1–2 segundos.',
    ],
    'Dormir': [
      'Mano cerca de la mejilla, quieta 1–2 segundos.',
    ],
  };

  static List<String> stepsFor(String phrase) =>
      steps[phrase] ??
      [
        'Haz la seña “$phrase” frente a la cámara.',
        'Mira la guía visual e imita la imagen.',
      ];

  static String labelFor(String phrase) =>
      phrase == 'Cómo' ? '¿Cómo estás?' : phrase;

  static IconData iconFor(String phrase) {
    switch (phrase) {
      case 'Hola':
        return Icons.waving_hand_rounded;
      case 'Cómo':
        return Icons.help_rounded;
      case 'Yo':
        return Icons.person_rounded;
      case 'Bien':
        return Icons.front_hand_rounded;
      case 'Sí':
        return Icons.thumb_up_rounded;
      case 'No':
        return Icons.swipe_rounded;
      case 'Gracias':
        return Icons.favorite_rounded;
      case 'Mal':
        return Icons.thumb_down_rounded;
      default:
        return Icons.sign_language_rounded;
    }
  }

  /// Pistas cortas para subtítulos / status en vivo.
  static const liveHint =
      'Puntos verdes = tus manos detectadas · Hola=arriba+vaivén amplio · '
      'Cómo=cara+vaivén corto · Yo=pecho · Bien=quieto · Sí=↑↓ · No=↔';
}
