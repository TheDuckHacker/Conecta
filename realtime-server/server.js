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

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    rooms: rooms.size,
    clients: wss ? wss.clients.size : 0,
    uptime: process.uptime(),
    ai: Boolean(process.env.GEMINI_API_KEY),
    tts: Boolean(process.env.ELEVENLABS_API_KEY),
  });
});

app.get('/', (_req, res) => {
  res.json({
    ok: true,
    service: 'conecta-realtime',
    ws: '/ws',
    health: '/health',
    ai: '/ai/compose',
    tts: '/tts',
  });
});

/**
 * Agente Gemini: señas → frase en español
 * POST /ai/compose { "signs": ["Hola","Bien"] }
 */
app.post('/ai/compose', async (req, res) => {
  const key = process.env.GEMINI_API_KEY;
  if (!key) {
    return res.status(503).json({ error: 'GEMINI_API_KEY no configurada' });
  }

  const signs = Array.isArray(req.body?.signs)
    ? req.body.signs.map((s) => String(s).trim()).filter(Boolean)
    : [];
  if (signs.length === 0) {
    return res.status(400).json({ error: 'signs requerido' });
  }

  const prompt =
    'Eres intérprete de lengua de señas hacia español latinoamericano (Bolivia). ' +
    'Recibes tokens de señas y debes devolver SOLO una frase natural en español, ' +
    'corta, sin comillas ni explicación.\nSeñas: ' +
    signs.join(' → ');

  try {
    const model = process.env.GEMINI_MODEL || 'gemini-2.0-flash';
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(key)}`;
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.2, maxOutputTokens: 120 },
      }),
    });
    const data = await r.json();
    if (!r.ok) {
      console.error('Gemini error', r.status, data);
      return res.status(502).json({ error: 'Gemini falló', detail: data });
    }
    const text =
      data?.candidates?.[0]?.content?.parts?.map((p) => p.text).join('') || '';
    const sentence = String(text).trim().replace(/^["']|["']$/g, '');
    return res.json({
      signs,
      sentence: sentence || signs.join(', ') + '.',
      source: 'gemini',
    });
  } catch (e) {
    console.error('Gemini', e);
    return res.status(500).json({ error: String(e.message || e) });
  }
});

/**
 * ElevenLabs TTS
 * POST /tts { "text": "Hola" } → audio/mpeg
 */
app.post('/tts', async (req, res) => {
  const key = process.env.ELEVENLABS_API_KEY;
  if (!key) {
    return res.status(503).json({ error: 'ELEVENLABS_API_KEY no configurada' });
  }
  const text = String(req.body?.text || '').trim();
  if (!text) return res.status(400).json({ error: 'text requerido' });

  const voiceId =
    process.env.ELEVENLABS_VOICE_ID || 'EXAVITQu4vr4xnSDxMaL';

  try {
    const r = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
      {
        method: 'POST',
        headers: {
          'xi-api-key': key,
          'Content-Type': 'application/json',
          Accept: 'audio/mpeg',
        },
        body: JSON.stringify({
          text,
          model_id: 'eleven_multilingual_v2',
          voice_settings: { stability: 0.45, similarity_boost: 0.8 },
        }),
      },
    );
    if (!r.ok) {
      const errText = await r.text();
      console.error('ElevenLabs', r.status, errText);
      return res.status(502).json({ error: 'ElevenLabs falló', detail: errText });
    }
    const buf = Buffer.from(await r.arrayBuffer());
    res.setHeader('Content-Type', 'audio/mpeg');
    res.setHeader('Cache-Control', 'no-store');
    return res.send(buf);
  } catch (e) {
    console.error('TTS', e);
    return res.status(500).json({ error: String(e.message || e) });
  }
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

    // Invitación de llamada → lobby personal del destinatario
    if (type === 'invite') {
      const target =
        String(msg.targetLobby || '').trim() ||
        (msg.toUserId ? `lobby:${msg.toUserId}` : '');
      const fromUserId = String(msg.fromUserId || msg.userId || meta.userId || '').trim();
      const roomId = String(msg.callRoomId || msg.roomId || '').trim();
      const fromName = String(msg.fromName || 'Contacto').trim();
      if (!target || !fromUserId || !roomId) return;

      const envelope = {
        type: 'invite',
        fromUserId,
        fromName,
        roomId,
        toUserId: String(msg.toUserId || '').trim(),
        at: new Date().toISOString(),
      };

      const lobby = rooms.get(target);
      if (lobby) {
        const raw = JSON.stringify(envelope);
        for (const client of lobby.values()) {
          if (client.ws.readyState === 1) client.ws.send(raw);
        }
      }
      return;
    }

    if (type === 'call_response') {
      const target =
        String(msg.targetLobby || '').trim() ||
        (msg.toUserId ? `lobby:${msg.toUserId}` : '');
      if (!target) return;
      const envelope = {
        type: 'call_response',
        fromUserId: String(msg.fromUserId || meta.userId || '').trim(),
        toUserId: String(msg.toUserId || '').trim(),
        roomId: String(msg.roomId || '').trim(),
        accepted: !!msg.accepted,
        at: new Date().toISOString(),
      };
      const lobby = rooms.get(target);
      if (lobby) {
        const raw = JSON.stringify(envelope);
        for (const client of lobby.values()) {
          if (client.ws.readyState === 1) client.ws.send(raw);
        }
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
