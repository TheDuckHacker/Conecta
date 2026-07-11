# Tasks: Conecta LSB — Comunicación accesible con traducción doble canal

**Input**: Design documents from `/specs/001-conecta-lsb-plataforma/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [quickstart.md](./quickstart.md)

**Tests**: Sin frameworks de test (constitución). Verificación: prueba manual del
flujo de demo + `check-classifier` contra muestras reservadas.

**Organization**: Agrupadas por fase del evento y user story. Regla de la
constitución: no empezar una story de menor prioridad si la anterior no está
demostrable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: puede hacerse en paralelo (archivos distintos, sin dependencias)
- **[Story]**: US1 (conversación presencial), US2 (llamada), US3 (aprendizaje)

---

## Phase 0: Pre-evento (preparación permitida — SIN código de producción)

- [ ] T001 [P] Definir la lista de 20–30 glosas LSB del vocabulario de demo
      (saludos, cortesía, necesidades, emergencia) con material de referencia
      de FEBOS/diccionarios LSB → documentar en `specs/001-conecta-lsb-plataforma/vocab-list.md`
- [ ] T002 [P] Conseguir material visual de referencia de cada seña (video/imagen)
      y validar con una persona usuaria de LSB si es posible
- [ ] T003 [P] Verificar en los teléfonos del equipo: Chrome Android soporta
      `SpeechRecognition` en español y MediaPipe corre fluido (probar demos
      oficiales de MediaPipe en el navegador del teléfono)
- [ ] T004 [P] Preparar cuentas: repo público GitHub, Vercel conectado, hotspot
      de respaldo para la demo
- [ ] T005 Ensayar el guion del pitch de 4 min contra la rúbrica (problema 20%,
      ejecución 25%, IA 20%, demo/UX 15%, potencial 20%)

**Checkpoint**: equipo llega al evento con vocabulario definido y stack validado.

---

## Phase 1: Setup (evento, hora 0–1)

- [ ] T006 Crear proyecto Vite + React + TypeScript en la raíz del repo
      (`npm create vite@latest`), estructura de carpetas según plan.md
- [ ] T007 [P] Instalar dependencias: `@mediapipe/tasks-vision`; configurar
      deploy automático a Vercel (HTTPS para cámara/micrófono)
- [ ] T008 [P] README inicial con problema, solución, stack e instrucciones
      (base: quickstart.md) — entregable obligatorio del evento

---

## Phase 2: Foundational (evento, horas 1–6) — BLOQUEA todas las stories

- [ ] T009 `src/vision/landmarks.ts`: captura de cámara + HandLandmarker de
      MediaPipe en vivo, con overlay de landmarks para depurar (≥15 fps en
      teléfono)
- [ ] T010 [P] `src/speech/stt.ts`: voz→texto con SpeechRecognition (es-BO,
      fallback es-419), con estados escuchando/error/no-soportado
- [ ] T011 [P] `src/speech/tts.ts`: texto→voz con speechSynthesis en español
- [ ] T012 [P] `src/conversation/`: modelo de Conversación y Mensaje (emisor,
      canal, contenido, confianza) en memoria + localStorage
- [ ] T013 `scripts/record-samples.ts` + página oculta de grabación: capturar y
      etiquetar muestras de landmarks por glosa → `src/vision/vocab.json`

**Checkpoint**: cámara, STT y TTS funcionan por separado en el teléfono.

---

## Phase 3: User Story 1 — Conversación presencial doble canal (P1) 🎯 MVP (horas 6–14)

**Goal**: una conversación por turnos seña↔voz en un solo teléfono.

**Independent Test**: 5 señas del vocabulario + respuestas habladas; ambas
partes reciben la traducción correcta (SC-003).

- [ ] T014 [US1] Grabar muestras del vocabulario completo con la luz del venue
      (10–20 muestras por glosa, personas distintas del equipo)
- [ ] T015 [US1] `src/vision/classifier.ts`: clasificador ligero
      (k-NN/MLP sobre landmarks normalizados) con umbral de confianza; por
      debajo del umbral → "no entendí" (FR-005)
- [ ] T016 [US1] `tests/classifier.check.ts` + script `npm run check-classifier`:
      precisión contra muestras reservadas, objetivo ≥ 80% (SC-002)
- [ ] T017 [US1] `src/components/ConversationView.tsx`: pantalla dividida con
      cámara, transcripción, historial con emisor y canal (FR-004)
- [ ] T018 [US1] Integración doble canal: seña reconocida → mensaje + TTS;
      botón de micrófono → STT → mensaje (flujo por turnos completo)
- [ ] T019 [US1] Entrada de texto de respaldo para ambas partes (FR-009)
- [ ] T020 [US1] Guía de encuadre/iluminación cuando no se detectan manos
      (edge case) y estados de error visibles sin audio (Principio IV)
- [ ] T021 [US1] Probar el Independent Test completo en el teléfono desplegado
      en Vercel; medir latencia < 3 s (SC-001)

**Checkpoint GATE**: US1 demostrable de punta a punta. Si no pasa, US2/US3 no
empiezan — se pule US1.

---

## Phase 4: User Story 2 — Llamada remota con traducción (P2) (horas 14–20)

**Goal**: videollamada entre dos teléfonos con subtítulos traducidos en ambos.

**Independent Test**: dos teléfonos en llamada; señas de un lado llegan como
texto/voz al otro y viceversa.

- [ ] T022 [US2] `src/call/peer.ts`: conexión PeerJS (video + data channel);
      pantalla de unirse por código simple
- [ ] T023 [US2] Enviar mensajes traducidos por data channel; render de
      subtítulos sobre el video remoto en ambos extremos
- [ ] T024 [US2] Degradación: si el video falla, el canal de texto sigue
      (escenario 3 de US2); probar con red limitada
- [ ] T025 [US2] Prueba del Independent Test con dos teléfonos en el venue

**Checkpoint**: US1 y US2 funcionan de forma independiente.

---

## Phase 5: User Story 3 — Aprendizaje de LSB (P3) (solo si sobra tiempo)

**Goal**: lección guiada de 5 señas con validación en vivo por cámara.

**Independent Test**: un novato completa la lección; la app valida aciertos y
errores de forma consistente.

- [ ] T026 [P] [US3] `src/learn/lessons.ts`: lección como secuencia de glosas del
      vocab existente + clips de demostración en `public/signs/`
- [ ] T027 [US3] `src/learn/PracticeView.tsx`: mostrar seña → practicar frente a
      cámara → feedback correcto/incorrecto reutilizando el clasificador de US1

---

## Phase 6: Polish & Submission (horas 20–24, deadline 8:30 AM)

- [ ] T028 Ensayo completo del pitch (4 min) con la demo en vivo; cronometrar
      (SC-004) y preparar video de respaldo (complementa, no reemplaza)
- [ ] T029 [P] README final: problema, solución, stack, instrucciones de
      ejecución, librerías/APIs usadas documentadas (regla del evento)
- [ ] T030 [P] Slides del pitch: problema local → demo → impacto/adopción
      (FEBOS, instituciones) → evolución (llamadas, aprendizaje, guaraní/
      quechua/aymara) → cómo se financia
- [ ] T031 Validar quickstart.md en una máquina limpia (SC-006)
- [ ] T032 Test de usabilidad con 2 personas ajenas al equipo (SC-005)
- [ ] T033 Freeze de código y **submission en el portal antes de las 8:30 AM**
      (las entregas tardías no se revisan)

---

## Dependencies & Execution Order

- **Phase 0** → antes del evento; **Phase 1 → 2** secuenciales al inicio.
- **US1 (Phase 3)** requiere Phase 2 completa. **GATE de constitución**: US2 y
  US3 solo empiezan con US1 demostrable.
- **US3** reutiliza el clasificador de US1 (T015) — depende de él directamente.
- **Phase 6** empieza como muy tarde en la hora 20 aunque US2/US3 estén
  incompletas: la submission a tiempo manda.

### Parallel Team Strategy (equipo de 2–4)

- Horas 1–6: Dev A → T009+T013 (visión), Dev B → T010–T012 (voz + modelo),
  Dev C/D → T008, vocabulario y grabación de muestras (T014).
- Horas 6–14: Dev A → clasificador (T015–T016), Dev B → UI (T017–T019),
  Dev C/D → pruebas en teléfono + material del pitch.
- Horas 14–20: solo si US1 pasó el gate, Dev A/B → US2; el resto pule y ensaya.

## Notes

- Commit después de cada tarea o grupo lógico; el repo debe quedar ejecutable
  en todo momento (constitución).
- Prueba manual del flujo de demo tras cada integración.
- Evitar: vocabulario grande e impreciso, features nuevas después de la hora 20,
  dependencia de la red del evento para P1.
