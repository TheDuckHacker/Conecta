# Conecta Realtime (Render)

Servidor WebSocket para subtítulos LSB y señalización de videollamada en tiempo real.

## Endpoints

- `GET /health` — estado
- `WS /ws` — salas (`join`, `caption`, `signal`, `leave`, `ping`)

## Local

```bash
cd realtime-server
npm install
npm start
```

## Render

Build: `cd realtime-server && npm install`  
Start: `cd realtime-server && node server.js`
