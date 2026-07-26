# Conecta Realtime (Render)

Servidor WebSocket para subtítulos LSB y señalización de videollamada en tiempo real.

## Endpoints

- `GET /health` — estado
- `POST /ai/compose` — señas → frase (`signs`, opcional `previous`, `locale`)
- `POST /tts` — texto → audio MPEG (ElevenLabs)
- `WS /ws` — salas (`join`, `caption`, `signal`, `leave`, `ping`)

Env: `GEMINI_API_KEY`, `GEMINI_MODEL` (opcional), `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`.

## Local

```bash
cd realtime-server
npm install
npm start
```

## Render

Build: `cd realtime-server && npm install`  
Start: `cd realtime-server && node server.js`
