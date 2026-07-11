# Conecta LSB

Plataforma de comunicación accesible para personas sordas mediante **Lengua de
Señas Boliviana (LSB)**: traducción doble canal en vivo (señas por cámara →
texto/voz en español, y voz → texto), llamadas con traducción y aprendizaje
visual de señas.

Proyecto para el **Cursor Buildathon Bolivia 2026** (25–26 de julio, Santa Cruz)
— Track **Social Impact AI**.

> ⚠️ Según las reglas del evento, el código se inicia durante la hackathon.
> Este repositorio contiene por ahora la documentación y especificación
> (preparación permitida).

## Documentación (spec-kit)

| Documento | Contenido |
|-----------|-----------|
| [Constitución](.specify/memory/constitution.md) | Principios del proyecto y restricciones del evento |
| [Especificación](specs/001-conecta-lsb-plataforma/spec.md) | Problema, público objetivo, user stories, requisitos y criterios de éxito |
| [Plan](specs/001-conecta-lsb-plataforma/plan.md) | Stack técnico, arquitectura y fases del evento |
| [Research](specs/001-conecta-lsb-plataforma/research.md) | Decisiones técnicas, alternativas y riesgos |
| [Quickstart](specs/001-conecta-lsb-plataforma/quickstart.md) | Cómo ejecutar la demo (base del README final) |
| [Tareas](specs/001-conecta-lsb-plataforma/tasks.md) | Plan de ejecución hora a hora para las 24 h del evento |

## Resumen del enfoque

- **PWA** (Vite + React + TypeScript) — corre en el navegador del teléfono, sin
  instalación de tienda.
- **MediaPipe** (landmarks de manos) + clasificador ligero entrenado con
  muestras propias para un vocabulario LSB de 20–30 señas.
- **Web Speech API** para voz→texto y texto→voz en español, sin backend.
- **PeerJS/WebRTC** solo para la llamada remota (P2).

Flujo de trabajo: [spec-kit](https://github.com/github/spec-kit) —
`/speckit-specify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-implement`.
