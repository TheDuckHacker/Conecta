# Conecta Realtime (Render)

Servidor WebSocket para subtítulos LSB y señalización de videollamada en tiempo real.

## Endpoints

- `GET /health` — estado
- `POST /ai/compose` — señas → frase (`signs`, opcional `previous`, `locale`)
- `POST /tts` — texto → audio MPEG (ElevenLabs)
- `POST /agent/help` — agente de ayuda in-app (Gemini + fallback)
- `GET /agent/zavu/status` — si Zavu está configurado
- `POST /agent/zavu/send` — enviar mensaje vía [Zavu](https://www.zavu.dev/es)
- `WS /ws` — salas (`join`, `caption`, `signal`, `leave`, `ping`)

## Variables de entorno

- `GEMINI_API_KEY`, `GEMINI_MODEL` (opcional)
- `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`
- `ZAVU_API_KEY` — API key de [Zavu](https://www.zavu.dev/es)
- `ZAVU_SENDER_ID` — sender de WhatsApp/SMS en Zavu (opcional)
- `ZAVU_WHATSAPP_NUMBER` — número E.164 o dígitos para `wa.me` (ej. `59170000000`)

## Local

```bash
cd realtime-server
npm install
npm start
```

## Render

Build: `cd realtime-server && npm install`  
Start: `cd realtime-server && node server.js`
