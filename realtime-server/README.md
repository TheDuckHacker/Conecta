# Conecta Realtime (Render)

Servidor WebSocket para subtítulos LSB y señalización de videollamada.

## Endpoints

- `GET /health`
- `POST /ai/compose` — señas → frase
- `POST /tts` — texto → audio
- `POST /agent/help` — agente de ayuda **dentro de Conecta**
- `WS /ws` — salas

## Variables (Render → Environment)

Para que Conecta funcione sola (sin WhatsApp):

- `GEMINI_API_KEY` — frases + agente de ayuda in-app
- `ELEVENLABS_API_KEY` — voz (opcional)

**No necesitas** `ZAVU_SENDER_ID` ni `ZAVU_WHATSAPP_NUMBER`.  
Zavu es otro producto (WhatsApp/SMS); tu app Conecta no los usa.

## Local

```bash
cd realtime-server
npm install
npm start
```

## Render

Build: `cd realtime-server && npm install`  
Start: `cd realtime-server && node server.js`
