# Implementation Plan: Conecta LSB — Comunicación accesible con traducción doble canal

**Branch**: `001-conecta-lsb-plataforma` | **Date**: 2026-07-11 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-conecta-lsb-plataforma/spec.md`

## Summary

App móvil-web (PWA) que traduce en doble canal: señas LSB capturadas por cámara
→ texto/voz en español, y voz en español → texto para la persona sorda.
Enfoque técnico: todo en el navegador del teléfono — MediaPipe para landmarks de
manos/pose + clasificador ligero de señas entrenado con muestras propias, Web
Speech API para voz↔texto. Sin backend para P1; WebRTC (PeerJS) solo para la
llamada remota (P2).

## Technical Context

**Language/Version**: TypeScript 5.x, Node.js 20+ (solo tooling)

**Primary Dependencies**: Vite + React 18, MediaPipe Tasks Vision
(HandLandmarker/GestureRecognizer), Web Speech API (SpeechRecognition +
speechSynthesis, es-BO/es-ES), PeerJS (solo P2)

**Storage**: Sin base de datos. Vocabulario LSB como JSON estático + clips de
demostración; historial de conversación en memoria/localStorage.

**Testing**: Prueba manual del flujo de demo tras cada integración (constitución);
un script de verificación del clasificador contra muestras grabadas.

**Target Platform**: Navegador móvil (Chrome Android) como experiencia principal;
funciona también en desktop para desarrollo. PWA instalable.

**Project Type**: Web app (single project, sin backend para P1)

**Performance Goals**: Traducción seña→voz < 3 s de punta a punta (SC-001);
inferencia de landmarks ≥ 15 fps en gama media; ≥ 80% de acierto sobre el
vocabulario de demo (SC-002).

**Constraints**: Debe tolerar internet limitado del evento — modelos y assets se
cargan una vez y P1 corre 100% en el dispositivo; HTTPS obligatorio para cámara
y micrófono (deploy en Vercel/Netlify o túnel local).

**Scale/Scope**: Demo de hackathon: ~20–30 señas LSB, 3 pantallas
(inicio, conversación, llamada), 2 dispositivos en simultáneo máximo.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principio | Cumplimiento |
|-----------|--------------|
| I. Adopción real sobre complejidad | ✅ PWA sin instalación de tienda, funciona en cualquier teléfono con Chrome; caso de uso presencial primero |
| II. Demo en vivo primero | ✅ P1 corre en el dispositivo sin depender de la red del evento; flujo de demo < 4 min |
| III. MVP por prioridad | ✅ P1 sin backend; P2 (WebRTC) y P3 (aprendizaje) solo si P1 está demostrable |
| IV. Accesibilidad | ✅ Todo audio tiene equivalente en texto; UI usable sin sonido; entrada de texto de respaldo (FR-009) |
| V. IA central, sin reinventar | ✅ MediaPipe + Web Speech como base; solo se entrena el clasificador ligero de señas con muestras propias |

Sin violaciones — no se requiere Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/001-conecta-lsb-plataforma/
├── plan.md              # Este archivo
├── spec.md              # Especificación
├── research.md          # Decisiones técnicas y alternativas
├── quickstart.md        # Cómo ejecutar la demo
└── tasks.md             # Tareas accionables (fase 2)
```

### Source Code (repository root)

```text
src/
├── vision/              # Captura de cámara, MediaPipe, clasificador de señas
│   ├── landmarks.ts     # Wrapper de HandLandmarker/GestureRecognizer
│   ├── classifier.ts    # Clasificador ligero (landmarks → glosa LSB)
│   └── vocab.json       # Vocabulario: glosa, categoría, muestras
├── speech/              # Voz a texto y texto a voz (Web Speech API)
│   ├── stt.ts
│   └── tts.ts
├── conversation/        # Modelo de conversación y mensajes (P1)
├── call/                # Señalización y datos WebRTC con PeerJS (P2)
├── learn/               # Módulo de aprendizaje (P3, solo si hay tiempo)
├── components/          # UI React: ConversationView, CameraPanel, Captions
├── App.tsx
└── main.tsx

public/
└── signs/               # Clips de demostración de señas (P3/guía)

scripts/
└── record-samples.ts    # Grabar/etiquetar muestras de landmarks para el vocab

tests/
└── classifier.check.ts  # Verificación del clasificador contra muestras grabadas
```

**Structure Decision**: Proyecto único Vite + React sin backend. Los módulos
`vision/`, `speech/` y `conversation/` implementan P1 completo en el navegador.
`call/` (P2) y `learn/` (P3) son directorios aislados que se agregan solo cuando
P1 esté demostrable, sin tocar el núcleo.

## Fases

- **Fase 0 (pre-evento, permitida)**: research.md, captura del vocabulario LSB
  de referencia (lista de 20–30 glosas validadas con material de FEBOS),
  quickstart.
- **Fase 1 (evento, horas 0–8)**: esqueleto Vite+React, cámara + landmarks en
  vivo, STT/TTS funcionando por separado.
- **Fase 2 (evento, horas 8–16)**: clasificador con muestras grabadas en sitio,
  vista de conversación doble canal (P1 completo), deploy HTTPS.
- **Fase 3 (evento, horas 16–22)**: P2 (llamada) si P1 es estable; si no, pulir
  UX y precisión. Ensayo del pitch con el flujo de demo.
- **Fase 4 (evento, horas 22–24)**: freeze, README final, slides, submission
  antes de las 8:30 AM.

## Complexity Tracking

Sin violaciones a la constitución — tabla no aplica.
