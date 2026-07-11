# Research: Conecta LSB

**Date**: 2026-07-11 | **Plan**: [plan.md](./plan.md)

## Decisiones técnicas

### D1: PWA en navegador vs app nativa (Android/Flutter/React Native)
**Decisión**: PWA (Vite + React) en Chrome Android.
**Razón**: Cero fricción de instalación para la demo y los jueces, acceso a
cámara/micrófono vía APIs web estándar, un solo código para desarrollo en
desktop y demo en teléfono. En 24 horas, compilar/firmar una app nativa es
riesgo puro sin beneficio para la rúbrica.
**Alternativas rechazadas**: Flutter/React Native (setup y build lentos, sin
ventaja para demo); app Android nativa (idem, y divide al equipo por skills).

### D2: Reconocimiento de señas — MediaPipe + clasificador propio ligero
**Decisión**: MediaPipe Tasks Vision (HandLandmarker, y PoseLandmarker si las
señas del vocabulario requieren brazos) corriendo en el navegador (WASM/GPU) +
clasificador ligero (k-NN o MLP pequeño sobre landmarks normalizados) entrenado
con muestras grabadas por el propio equipo.
**Razón**: No existe modelo público de LSB. Los landmarks reducen el problema a
clasificar vectores de ~63–225 dims, entrenable en minutos con 10–20 muestras
por seña. Corre offline en el dispositivo (restricción de internet del evento).
**Alternativas rechazadas**: entrenar CNN sobre video (no hay dataset LSB ni
tiempo); enviar frames a un LLM multimodal por API (latencia > 3 s, costo,
dependencia de red); Teachable Machine (válido como plan B rápido, pero menos
control sobre señas dinámicas).
**Nota**: señas dinámicas (movimiento) se clasifican sobre una ventana de
landmarks (secuencia corta), no frame a frame. Empezar con señas estáticas del
vocabulario y agregar dinámicas si el tiempo alcanza.

### D3: Voz a texto y texto a voz — Web Speech API
**Decisión**: `SpeechRecognition` (STT, `lang: es-BO` con fallback `es-419`/`es-ES`)
y `speechSynthesis` (TTS) del navegador.
**Razón**: Gratis, sin backend, latencia baja, soporte español correcto en
Chrome Android. Cumple FR-002/FR-003 sin infraestructura.
**Alternativas rechazadas**: Whisper API / Google STT (red + costo + latencia);
Whisper local WASM (pesado para gama media).
**Riesgo**: SpeechRecognition en Chrome usa red para el reconocimiento; si el
WiFi del evento falla, el respaldo es la entrada de texto (FR-009). Probar con
hotspot propio como plan B.

### D4: Llamada remota (P2) — PeerJS
**Decisión**: WebRTC con PeerJS (broker público) + data channel para los
subtítulos traducidos; la traducción corre en el dispositivo de origen.
**Razón**: P2 en horas, no días. El data channel garantiza que el texto llegue
aunque el video se degrade (escenario de aceptación 3 de US2).
**Alternativas rechazadas**: servidor de señalización propio (innecesario);
plataformas CPaaS tipo Twilio (costo, cuentas, tiempo de setup).

### D5: Vocabulario LSB de demo
**Decisión**: 20–30 glosas en categorías saludo/cortesía/necesidades/emergencia,
validadas contra material de referencia de FEBOS y diccionarios LSB públicos;
muestras grabadas por el equipo durante el evento con el script
`scripts/record-samples.ts`.
**Razón**: FR-010; un vocabulario chico y bien reconocido gana a uno grande e
impreciso (SC-002 pesa más que la cobertura).
**Pendiente pre-evento**: confirmar la lista exacta de glosas y conseguir
material de referencia visual de cada seña.

### D6: Deploy — Vercel (o Netlify)
**Decisión**: Deploy continuo a Vercel desde el repo público.
**Razón**: HTTPS obligatorio para cámara/micrófono en móvil; URL pública que los
jueces pueden abrir; "demo en producción" suma en la rúbrica.

## Riesgos principales

| Riesgo | Prob. | Mitigación |
|--------|-------|------------|
| Precisión del clasificador < 80% | Media | Vocabulario chico, señas visualmente distintas entre sí, grabar muestras con la misma luz del venue, umbral de confianza con "no entendí" (FR-005) |
| WiFi del evento inestable rompe STT | Media | P1 visual corre offline; hotspot propio; entrada de texto de respaldo |
| Señas dinámicas difíciles en el tiempo disponible | Alta | Empezar con estáticas; ventana de secuencia solo si sobra tiempo |
| P2 (WebRTC) consume el tiempo de pulir P1 | Media | Gate de la constitución: P2 no empieza hasta que P1 pase su Independent Test |
