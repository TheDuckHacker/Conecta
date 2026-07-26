/**
 * Conecta LSB — servidor realtime (Render)
 *
 * - HTTP /health
 * - WebSocket /ws
 *   join | caption | signal | leave | ping
 *
 * Mensajes JSON:
 * { "type": "join", "roomId": "...", "userId": "...", "role": "deaf|hearing" }
 * { "type": "caption", "roomId": "...", "userId": "...", "text": "...", "role": "sign|speech|typed" }
 * { "type": "signal", "roomId": "...", "userId": "...", "to": "...", "payload": { ... } }
 * { "type": "leave", "roomId": "...", "userId": "..." }
 */
const http = require('http');
const express = require('express');
const cors = require('cors');
const { WebSocketServer } = require('ws');
const { randomUUID } = require('crypto');

const PORT = process.env.PORT || 10000;

const app = express();
app.use(cors());
app.use(express.json({ limit: '1mb' }));

app.get('/', (_req, res) => {
  res.json({
    ok: true,
    service: 'conecta-realtime',
    ws: '/ws',
    health: '/health',
  });
});

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    rooms: rooms.size,
    clients: wss ? wss.clients.size : 0,
    uptime: process.uptime(),
  });
});

/** roomId -> Map(userId -> { ws, role, joinedAt }) */
const rooms = new Map();

function getRoom(roomId) {
  if (!rooms.has(roomId)) rooms.set(roomId, new Map());
  return rooms.get(roomId);
}

function broadcast(roomId, message, exceptUserId = null) {
  const room = rooms.get(roomId);
  if (!room) return;
  const raw = JSON.stringify(message);
  for (const [uid, client] of room.entries()) {
    if (exceptUserId && uid === exceptUserId) continue;
    if (client.ws.readyState === 1) {
      client.ws.send(raw);
    }
  }
}

function leaveRoom(roomId, userId) {
  const room = rooms.get(roomId);
  if (!room) return;
  room.delete(userId);
  broadcast(roomId, {
    type: 'peer_left',
    roomId,
    userId,
    peers: [...room.keys()],
  });
  if (room.size === 0) rooms.delete(roomId);
}

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws) => {
  const meta = { userId: null, roomId: null, id: randomUUID() };

  ws.send(
    JSON.stringify({
      type: 'welcome',
      connectionId: meta.id,
      serverTime: new Date().toISOString(),
    }),
  );

  ws.on('message', (buf) => {
    let msg;
    try {
      msg = JSON.parse(buf.toString());
    } catch {
      ws.send(JSON.stringify({ type: 'error', message: 'JSON inválido' }));
      return;
    }

    const type = msg.type;
    if (type === 'ping') {
      ws.send(JSON.stringify({ type: 'pong', t: Date.now() }));
      return;
    }

    if (type === 'join') {
      const roomId = String(msg.roomId || '').trim();
      const userId = String(msg.userId || '').trim();
      if (!roomId || !userId) {
        ws.send(JSON.stringify({ type: 'error', message: 'roomId y userId requeridos' }));
        return;
      }

      // Salir de sala anterior
      if (meta.roomId && meta.userId) {
        leaveRoom(meta.roomId, meta.userId);
      }

      meta.roomId = roomId;
      meta.userId = userId;
      const room = getRoom(roomId);
      room.set(userId, {
        ws,
        role: msg.role || 'unknown',
        joinedAt: Date.now(),
      });

      const peers = [...room.entries()]
        .filter(([uid]) => uid !== userId)
        .map(([uid, c]) => ({ userId: uid, role: c.role }));

      ws.send(
        JSON.stringify({
          type: 'joined',
          roomId,
          userId,
          peers,
        }),
      );

      broadcast(
        roomId,
        {
          type: 'peer_joined',
          roomId,
          userId,
          role: msg.role || 'unknown',
          peers: [...room.keys()],
        },
        userId,
      );
      return;
    }

    if (type === 'caption') {
      const roomId = String(msg.roomId || meta.roomId || '').trim();
      const userId = String(msg.userId || meta.userId || '').trim();
      const text = String(msg.text || '').trim();
      if (!roomId || !userId || !text) return;

      broadcast(
        roomId,
        {
          type: 'caption',
          roomId,
          userId,
          text,
          role: msg.role || 'typed',
          at: new Date().toISOString(),
        },
        userId,
      );
      return;
    }

    if (type === 'signal') {
      // Señalización WebRTC (offer/answer/ice) hacia un peer o a toda la sala
      const roomId = String(msg.roomId || meta.roomId || '').trim();
      const userId = String(msg.userId || meta.userId || '').trim();
      if (!roomId || !userId || !msg.payload) return;

      const room = rooms.get(roomId);
      if (!room) return;

      const envelope = {
        type: 'signal',
        roomId,
        userId,
        payload: msg.payload,
        at: new Date().toISOString(),
      };

      if (msg.to && room.has(msg.to)) {
        const peer = room.get(msg.to);
        if (peer.ws.readyState === 1) {
          peer.ws.send(JSON.stringify({ ...envelope, to: msg.to }));
        }
      } else {
        broadcast(roomId, envelope, userId);
      }
      return;
    }

    if (type === 'leave') {
      if (meta.roomId && meta.userId) {
        leaveRoom(meta.roomId, meta.userId);
        meta.roomId = null;
        meta.userId = null;
      }
      return;
    }

    ws.send(JSON.stringify({ type: 'error', message: `Tipo desconocido: ${type}` }));
  });

  ws.on('close', () => {
    if (meta.roomId && meta.userId) {
      leaveRoom(meta.roomId, meta.userId);
    }
  });
});

server.listen(PORT, () => {
  console.log(`Conecta realtime listening on :${PORT}`);
});
