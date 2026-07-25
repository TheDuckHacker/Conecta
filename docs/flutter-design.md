# Diseño técnico: Conecta LSB en Flutter

> Este documento describe la arquitectura, estructura de carpetas, paquetes y flujo de datos para implementar Conecta LSB como aplicación Flutter (Android/iOS). Se limita a diseño técnico y boilerplate; la lógica de negocio se inicia durante el hackathon según la constitución del proyecto.

## 1. Stack técnico Flutter

| Capa | Paquete / Tecnología | Razón |
|------|----------------------|-------|
| Framework | Flutter 3.22+ / Dart 3.4+ | UI única para Android/iOS, acceso nativo a cámara/micrófono |
| Cámara | `camera: ^0.11.0` | Preview nativo, control de resolución, fps y exposición |
| Visión / landmarks | `google_mlkit_hand_detection: ^0.14.0` + `google_mlkit_pose_detection` | Detección de manos y pose en el dispositivo, sin red |
| Clasificador de señas | `tflite_flutter: ^0.11.0` | Clasificador ligero entrenado con landmarks (mLP/k-NN) |
| Voz a texto | `speech_to_text: ^6.6.0` | Reconocimiento de voz en español (es-BO / es-ES) |
| Texto a voz | `flutter_tts: ^4.0.0` | Síntesis de voz en español |
| Llamadas WebRTC | `flutter_webrtc: ^0.11.0` | Videollamada P2P entre dos dispositivos |
| Señalización | `firebase_core` + `cloud_firestore` (o PeerJS-server auto-hospedado) | Intercambio de IDs/códigos de sala para WebRTC |
| Estado | `flutter_bloc: ^8.1.0` + `freezed` | Gestión de estado predecible para conversación, cámara, llamada |
| Inyección | `get_it: ^7.7.0` | Servicios singleton (cámara, TTS, STT, clasificador) |
| Almacenamiento local | `hive: ^2.2.0` / `shared_preferences` | Historial de conversación, vocabulario, preferencias |
| Routing | `go_router: ^14.0.0` | Navegación declarativa |
| UI accesible | `flutter_local_notifications` + `vibration` | Feedback visual y háptico sin depender del audio |
| Logging | `logger: ^2.0.0` | Logs durante demo sin frameworks pesados |

## 2. Estructura de carpetas

```text
lib/
├── main.dart                         # Punto de entrada, inyección de dependencias
├── app.dart                          # MaterialApp + router + tema accesible
├── config/
│   ├── routes.dart                   # GoRouter: /, /conversation, /call, /learn
│   ├── theme.dart                    # Colores, tipografía accesible, tamaños grandes
│   └── constants.dart                # Vocabulario por defecto, timeouts, idiomas
├── core/
│   ├── models/                       # Entidades puras (User, Message, Sign, Lesson)
│   ├── errors/                       # Excepciones de dominio
│   └── utils/                        # Normalización de landmarks, helpers
├── features/
│   ├── home/                         # Pantalla de inicio
│   │   ├── presentation/
│   │   │   ├── home_screen.dart
│   │   │   └── widgets/
│   │   └── logic/
│   │       └── home_cubit.dart
│   ├── conversation/                 # P1: conversación presencial doble canal
│   │   ├── data/
│   │   │   ├── local/
│   │   │   │   └── conversation_local_source.dart
│   │   │   └── repositories/
│   │   │       └── conversation_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── conversation.dart
│   │   │   │   └── message.dart
│   │   │   ├── repositories/
│   │   │   │   └── conversation_repository.dart
│   │   │   └── usecases/
│   │   │       ├── send_sign_message.dart
│   │   │       ├── send_voice_message.dart
│   │   │       └── send_text_message.dart
│   │   └── presentation/
│   │       ├── conversation_screen.dart
│   │       ├── conversation_cubit.dart
│   │       └── widgets/
│   │           ├── camera_panel.dart
│   │           ├── sign_recognition_overlay.dart
│   │           ├── message_bubble.dart
│   │           ├── voice_button.dart
│   │           └── text_fallback_input.dart
│   ├── vision/                       # Motor de visión (cámara + landmarks + clasificador)
│   │   ├── data/
│   │   │   ├── camera_service.dart
│   │   │   ├── hand_detector.dart
│   │   │   ├── sign_classifier.dart
│   │   │   └── vocab_data_source.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── hand_landmarks.dart
│   │   │   │   └── classified_sign.dart
│   │   │   └── repositories/
│   │   │       └── vision_repository.dart
│   │   └── presentation/
│   │       └── camera_preview_widget.dart
│   ├── speech/                       # STT + TTS
│   │   ├── data/
│   │   │   ├── speech_to_text_service.dart
│   │   │   └── text_to_speech_service.dart
│   │   ├── domain/
│   │   │   └── speech_repository.dart
│   │   └── presentation/
│   │       ├── stt_button.dart
│   │       └── tts_button.dart
│   ├── call/                         # P2: llamada remota WebRTC
│   │   ├── data/
│   │   │   ├── signaling_service.dart
│   │   │   └── webrtc_service.dart
│   │   ├── domain/
│   │   │   └── call_repository.dart
│   │   └── presentation/
│   │       ├── call_screen.dart
│   │       ├── call_cubit.dart
│   │       └── widgets/
│   │           ├── remote_video.dart
│   │           ├── local_video.dart
│   │           └── captions_overlay.dart
│   └── learn/                        # P3: aprendizaje de LSB
│       ├── data/
│       │   └── lessons_data_source.dart
│       ├── domain/
│       │   └── lesson_repository.dart
│       └── presentation/
│           ├── learn_screen.dart
│           ├── lesson_screen.dart
│           └── practice_screen.dart
└── services/
    └── service_locator.dart          # GetIt: registra cámara, TTS, STT, etc.

assets/
├── vocab.json                        # Lista de glosas, categorías, clips demo
├── models/
│   └── sign_classifier.tflite        # Modelo entrenado con landmarks
└── signs/                            # GIFs/videos de demostración de cada seña

android/
ios/
linux/
macos/
windows/
web/
test/
├── vision/
│   └── sign_classifier_test.dart
├── speech/
│   └── stt_tts_test.dart
└── conversation/
    └── conversation_cubit_test.dart

pubspec.yaml
README.md
```

## 3. Arquitectura: Clean Architecture + BLoC

```text
UI (Widgets) -> BLoC/Cubit -> UseCase -> Repository -> DataSource -> Nativo/Servicio
```

- **Presentación**: pantallas y widgets puramente UI.
- **Lógica**: `Cubit` con estados inmutables (`freezed`).
- **Dominio**: entidades, contratos de repositorio, casos de uso.
- **Datos**: implementaciones concretas de cámara, ML Kit, TTS, STT, WebRTC, Hive.

## 4. Entidades principales

```dart
// lib/core/models/message.dart
enum Channel { sign, voice, text }

class Message {
  final String id;
  final Channel channel;
  final String senderId;      // 'sorda' | 'oyente'
  final String content;       // texto traducido/escrito
  final String? originalSign; // glosa LSB si channel == sign
  final double confidence;    // 0.0 - 1.0
  final DateTime timestamp;
}

// lib/core/models/sign.dart
class Sign {
  final String gloss;         // glosa en español
  final String category;      // saludo, cortesía, necesidad, emergencia
  final String? demoAsset;    // ruta del video/gif
  final List<double>? sampleLandmarks;
}

// lib/core/models/classified_sign.dart
class ClassifiedSign {
  final String gloss;
  final double confidence;
  final bool isBelowThreshold;
}
```

## 5. Flujo de datos: P1 — Conversación presencial

```text
1. Cámara -> CameraController -> ML Kit Hand Detector -> List<HandLandmarks>
2. HandLandmarks -> normalización -> SignClassifier -> ClassifiedSign
3. Si confidence >= threshold:
   ClassifiedSign -> Message(channel: sign) -> ConversationRepository -> UI + TTS
4. Si confidence < threshold:
   UI muestra "No entendí, repite por favor" (FR-005)
5. Botón de micrófono -> speech_to_text -> Message(channel: voice) -> UI
6. Botón de texto -> Message(channel: text) -> UI
7. TTS lee el mensaje de signo/texto en voz alta para el oyente
```

## 6. Flujo de datos: P2 — Llamada remota

```text
1. Usuario A genera/ingresa un código de sala
2. SignalingService (Firestore) intercambia SDP/ICE entre A y B
3. WebRTC establece video/audio peer-to-peer
4. En cada dispositivo:
   - Señas locales -> clasificador -> Message -> DataChannel -> otro extremo
   - Voz local -> STT -> Message -> DataChannel -> otro extremo
   - DataChannel recibe mensajes -> UI como subtítulos sobre el video
5. Si video falla, DataChannel de texto sigue funcionando
```

## 7. Estados de la UI para P1

```dart
class ConversationState {
  final List<Message> messages;
  final bool isCameraReady;
  final bool isListening;
  final bool isProcessingSign;
  final String? guidanceMessage; // "Acerca las manos", "Más luz", etc.
  final Failure? failure;
}
```

## 8. Consideraciones de accesibilidad

- **Toda salida de audio tiene equivalente visual**: TTS solo complementa el texto mostrado en pantalla.
- **Feedback háptico**: vibración corta al reconocer una seña, al inicio/fin de STT, al error.
- **Alto contraste**: textos oscuros sobre fondo claro, botones con bordes visibles.
- **Iconos + texto**: ningún botón solo con icono.
- **Sin animaciones que causen mareo**: transiciones suaves, desactivables.
- **Tamaños de toque**: mínimo 56 x 56 dp.

## 9. Riesgos y mitigaciones específicas de Flutter

| Riesgo | Mitigación |
|--------|------------|
| ML Kit no detecta manos en baja luz | Guía visual de encuadre + umbral de confianza |
| `speech_to_text` requiere permisos en Android 13+ | Solicitar permisos al inicio de la conversación |
| WebRTC consume batería en móvil | P2 solo si P1 es estable; conexión corta en demo |
| Tamaño del modelo TFLite | Usar clasificador pequeño (< 1 MB) sobre landmarks |
| Latencia de cámara | `ResolutionPreset.medium`, procesar cada 2-3 frames |

## 10. Próximos pasos

1. Generar el proyecto con `flutter create --org com.conecta.lsb conecta_lsb`.
2. Añadir dependencias del `pubspec.yaml`.
3. Configurar permisos de cámara, micrófono y vibración en `AndroidManifest.xml` e `Info.plist`.
4. Implementar el `VisionRepository` (cámara + ML Kit + clasificador) primero; bloquea toda la demo.
5. Después de P1 estable, agregar `CallRepository` con WebRTC.

## 11. Ejemplo de pubspec.yaml

```yaml
name: conecta_lsb
description: Plataforma de comunicación accesible con LSB.
publish_to: 'none'
version: 0.1.0

environment:
  sdk: '>=3.4.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  camera: ^0.11.0
  google_mlkit_hand_detection: ^0.14.0
  google_mlkit_pose_detection: ^0.13.0
  tflite_flutter: ^0.11.0
  speech_to_text: ^6.6.0
  flutter_tts: ^4.0.0
  flutter_webrtc: ^0.11.0
  firebase_core: ^3.0.0
  cloud_firestore: ^5.0.0
  flutter_bloc: ^8.1.0
  freezed_annotation: ^2.4.0
  get_it: ^7.7.0
  hive: ^2.2.0
  hive_flutter: ^1.1.0
  go_router: ^14.0.0
  flutter_local_notifications: ^17.0.0
  vibration: ^1.9.0
  logger: ^2.0.0
  cupertino_icons: ^1.0.6

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  build_runner: ^2.4.0
  freezed: ^2.5.0
  json_serializable: ^6.8.0
  hive_generator: ^2.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/vocab.json
    - assets/models/sign_classifier.tflite
    - assets/signs/
```

---

**Nota**: Este documento es diseño técnico. La implementación de la lógica de negocio sigue el flujo de la constitución: P1 primero, P2 solo si P1 es demostrable, P3 si sobra tiempo.
