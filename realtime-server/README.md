# Conecta Realtime (Render)

Servidor WebSocket para subtítulos LSB y señalización de videollamada.

## Endpoints

- `GET /` — catálogo de endpoints
- `GET /health` — estado del servidor
- `POST /ai/compose` — señas → frase (protegido)
- `POST /tts` — texto → audio (protegido)
- `POST /agent/help` — agente de ayuda **dentro de Conecta** (protegido)
- `GET /agent/zavu/status` — estado de Zavu
- `POST /agent/zavu/send` — enviar vía Zavu (protegido)
- `POST /call/invite` — invitar a videollamada (protegido)
- `WS /ws` — salas de videollamada

## Variables (Render → Environment)

### Requeridas para Conecta

- `GEMINI_API_KEY` — frases + agente de ayuda in-app (obtener en [Google AI Studio](https://aistudio.google.com/app/apikey))
- `ELEVENLABS_API_KEY` — voz (opcional, obtener en [ElevenLabs](https://elevenlabs.io))

### Opcional: modelo Gemini

- `GEMINI_MODEL` — por defecto `gemini-2.0-flash-exp`; si falla, intenta `gemini-1.5-flash`

### Seguridad (recomendado para producción)

- `CONECTA_API_KEY` — clave compartida para proteger endpoints HTTP sensibles
  - Cuando está configurada, las rutas `/ai/compose`, `/tts`, `/agent/help`, `/agent/zavu/send` y `/call/invite` requieren el header `X-Conecta-Key: <tu-clave>` o `Authorization: Bearer <tu-clave>`
  - Cuando no está configurada, las rutas quedan abiertas (solo para desarrollo local)
  - **Importante:** Configura la misma clave en el cliente Flutter con `--dart-define=CONECTA_API_KEY=<tu-clave>`

### Opcional: Zavu (WhatsApp/SMS)

**No necesitas** Zavu para que Conecta funcione. Es un servicio externo opcional.

- `ZAVU_API_KEY` — API key de [Zavu](https://www.zavu.dev/es)
- `ZAVU_SENDER_ID` — ID del remitente (requerido para enviar mensajes)
- `ZAVU_WHATSAPP_NUMBER` — número de WhatsApp del remitente

El servidor reporta `zavuReady: true` solo cuando `ZAVU_API_KEY` y `ZAVU_SENDER_ID` están configurados.

## Local

```bash
cd realtime-server
npm install
npm start
```

## Render

Build: `cd realtime-server && npm install`  
Start: `cd realtime-server && node server.js`
