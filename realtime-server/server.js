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
    zavu: Boolean(process.env.ZAVU_API_KEY),
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
    help: '/agent/help',
    zavu: '/agent/zavu/status',
  });
});

const LSB_VOCAB = [
  'Hola', 'Cómo', 'Estás', 'Sí', 'No', 'Bien', 'Mal', 'Yo', 'Gracias',
  'Por favor', 'Dolor', 'Ayuda', 'Doctor', 'Hoy', 'Mamá', 'Papá', 'Comer',
  'Beber', 'Dormir', 'Adiós',
];

const ESTADOS = { Bien: 'bien', Mal: 'mal' };
const ACCIONES = { Comer: 'comer', Beber: 'beber', Dormir: 'dormir' };

/**
 * Fallback local si Gemini no está o falla. Respeta el ORDEN de las señas:
 * [Hola, Cómo, Yo, Bien] → "Hola, ¿cómo estás? Yo estoy bien."
 */
function composeLocal(signs) {
  if (!signs.length) return '';
  const segments = [];
  let i = 0;

  while (i < signs.length) {
    const sign = signs[i];
    const next = signs[i + 1];

    if (sign === 'Hola' || sign === 'Adiós') {
      segments.push(sign);
      i += 1;
    } else if (sign === 'Cómo' || sign === 'Estás') {
      segments.push('¿cómo estás?');
      i += signs[i + 1] === 'Estás' ? 2 : 1;
    } else if (sign === 'Yo') {
      if (ESTADOS[next]) {
        segments.push(`yo estoy ${ESTADOS[next]}`);
        i += 2;
      } else if (ACCIONES[next]) {
        segments.push(`yo quiero ${ACCIONES[next]}`);
        i += 2;
      } else if (next === 'Dolor') {
        segments.push('yo tengo dolor');
        i += 2;
      } else if (next === 'Ayuda') {
        segments.push('yo necesito ayuda');
        i += 2;
      } else if (next === 'Doctor') {
        segments.push('yo necesito un doctor');
        i += 2;
      } else {
        segments.push('yo');
        i += 1;
      }
    } else if (ESTADOS[sign]) {
      segments.push(`estoy ${ESTADOS[sign]}`);
      i += 1;
    } else if (ACCIONES[sign]) {
      segments.push(`quiero ${ACCIONES[sign]}`);
      i += 1;
    } else if (sign === 'Dolor') {
      segments.push(next === 'Doctor' ? 'tengo dolor, necesito un doctor' : 'tengo dolor');
      i += next === 'Doctor' ? 2 : 1;
    } else if (sign === 'Ayuda') {
      segments.push(next === 'Doctor' ? 'necesito ayuda del doctor' : 'necesito ayuda');
      i += next === 'Doctor' ? 2 : 1;
    } else if (sign === 'Doctor') {
      segments.push('necesito un doctor');
      i += 1;
    } else if (sign === 'Mamá' || sign === 'Papá') {
      segments.push(`es mi ${sign.toLowerCase()}`);
      i += 1;
    } else {
      segments.push(String(sign).toLowerCase());
      i += 1;
    }
  }

  return joinSegments(segments);
}

function joinSegments(segments) {
  if (!segments.length) return '';
  let out = '';
  let startOfSentence = true;

  segments.forEach((raw, index) => {
    let seg = raw;
    const isQuestion = seg.endsWith('?');
    if (startOfSentence) {
      seg = seg.startsWith('¿')
        ? `¿${seg[1].toUpperCase()}${seg.slice(2)}`
        : seg[0].toUpperCase() + seg.slice(1);
    } else {
      out += ', ';
    }
    out += seg;

    const last = index === segments.length - 1;
    if (isQuestion) {
      if (!last) out += ' ';
      startOfSentence = true;
    } else if (last) {
      out += '.';
    } else {
      startOfSentence = false;
    }
  });

  return out;
}

function cleanSentence(text) {
  return String(text || '')
    .trim()
    .replace(/^["'«»]+|["'«»]+$/g, '')
    .replace(/^frase\s*:\s*/i, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Agente Gemini: señas → frase en español (Bolivia)
 * POST /ai/compose
 * { "signs": ["Hola","Bien"], "previous"?: "...", "locale"?: "es-BO" }
 */
app.post('/ai/compose', async (req, res) => {
  const signs = Array.isArray(req.body?.signs)
    ? req.body.signs.map((s) => String(s).trim()).filter(Boolean)
    : [];
  if (signs.length === 0) {
    return res.status(400).json({ error: 'signs requerido' });
  }

  const previous = String(req.body?.previous || '').trim();
  const locale = String(req.body?.locale || 'es-BO').trim();
  const localSentence = composeLocal(signs);

  const key = process.env.GEMINI_API_KEY;
  if (!key) {
    return res.json({
      signs,
      sentence: localSentence,
      source: 'local',
      confidence: 0.55,
      note: 'GEMINI_API_KEY no configurada',
    });
  }

  const prompt = [
    'Eres intérprete de Lengua de Señas hacia español latinoamericano (Bolivia).',
    'Convierte tokens de señas en UNA frase natural, corta y hablable.',
    'Reglas: solo la frase; sin comillas, sin markdown, sin explicación.',
    'No inventes señas que no estén en la secuencia.',
    'Respeta el orden de las señas y usa signos de pregunta cuando toque.',
    'Ejemplos: "Hola → Cómo" = Hola, ¿cómo estás?; ' +
      '"Hola → Cómo → Yo → Bien" = Hola, ¿cómo estás? Yo estoy bien.; ' +
      '"Yo → Dolor" = Yo tengo dolor.',
    `Vocabulario frecuente: ${LSB_VOCAB.join(', ')}.`,
    `Locale: ${locale}.`,
    previous ? `Frase anterior (refina si encaja): ${previous}` : '',
    `Señas en orden: ${signs.join(' → ')}`,
  ]
    .filter(Boolean)
    .join('\n');

  try {
    const model = process.env.GEMINI_MODEL || 'gemini-flash-latest';
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(key)}`;
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.15, maxOutputTokens: 80 },
      }),
    });
    const data = await r.json();
    if (!r.ok) {
      console.error('Gemini error', r.status, data);
      return res.json({
        signs,
        sentence: localSentence,
        source: 'local',
        confidence: 0.5,
        note: 'gemini_fallback',
      });
    }
    const text =
      data?.candidates?.[0]?.content?.parts?.map((p) => p.text).join('') || '';
    const sentence = cleanSentence(text) || localSentence;
    return res.json({
      signs,
      sentence,
      source: 'gemini',
      confidence: 0.9,
    });
  } catch (e) {
    console.error('Gemini', e);
    return res.json({
      signs,
      sentence: localSentence,
      source: 'local',
      confidence: 0.45,
      note: String(e.message || e),
    });
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

/** Sesiones del agente de ayuda (en memoria). */
const helpSessions = new Map();

const HELP_SYSTEM = [
  'Eres el asistente de Conecta LSB (Lengua de Señas Boliviana).',
  'Responde en español, claro y breve (máx. 6 líneas).',
  'Las señas de la app coinciden con la guía visual (6 paneles):',
  '- HOLA: mano abierta BIEN ARRIBA junto a la cabeza + vaivén lado a lado.',
  '- ¿CÓMO ESTÁS?: mano cerca de barbilla/mejilla + movimiento corto lado a lado.',
  '- YO: índice apuntando al pecho, quieto.',
  '- BIEN: mano al pecho, palma al frente, quieta.',
  '- SÍ: pecho + movimiento arriba/abajo (pulgar arriba).',
  '- NO: mano plana al pecho + vaivén lado a lado.',
  'Ayudas con Traducción, Academia, videollamada y esas señas.',
  'Si no sabes, sugiere Academia → curso y mirar la imagen de la guía.',
].join('\n');

function helpLocalReply(message) {
  const m = String(message || '').toLowerCase();
  if (m.includes('hola') || m.includes('saludo')) {
    return 'Para decir Hola: levanta la mano abierta BIEN ARRIBA (junto a la cabeza) y muévela de lado a lado 1–2 segundos. Luego abre Academia → Saludos para practicar con pasos.';
  }
  if (m.includes('cómo estás') || m.includes('como estas') || m.includes('cómo')) {
    return 'Para ¿Cómo estás?: acerca la mano a la cara (mejilla/barbilla) y haz un movimiento corto de lado a lado. En Academia la seña se llama “Cómo”.';
  }
  if (m.includes('academia') || m.includes('aprender') || m.includes('práctica')) {
    return 'En Academia LSB: 1) Toca “Cómo empezar”. 2) Elige un curso. 3) Lee los pasos numerados. 4) Toca “Practicar con cámara”.';
  }
  if (m.includes('whatsapp') || m.includes('zavu') || m.includes('sender')) {
    return 'Conecta es tu app propia. La ayuda está dentro: Inicio → Agente de ayuda, o el botón Ayuda en la videollamada. No hace falta WhatsApp ni Zavu.';
  }
  if (m.includes('traduc') || m.includes('cámara') || m.includes('camara')) {
    return 'En Traducción: permite la cámara, buena luz, pecho visible. Usa el botón del libro para ver la guía de señas. Las palabras se arman en frase (IA en servidor o local).';
  }
  return 'Puedo ayudarte con Hola, ¿Cómo estás?, Academia, Traducción y WhatsApp (Zavu). Pregunta, por ejemplo: “¿cómo hago Hola?” o “¿cómo uso la Academia?”.';
}

async function geminiHelp(history, userMessage) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return null;
  const model = process.env.GEMINI_MODEL || 'gemini-flash-latest';
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(key)}`;
  const contents = [
    { role: 'user', parts: [{ text: HELP_SYSTEM }] },
    { role: 'model', parts: [{ text: 'Entendido. Ayudaré con Conecta LSB de forma clara y breve.' }] },
    ...history.slice(-8).map((h) => ({
      role: h.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: h.text }],
    })),
    { role: 'user', parts: [{ text: userMessage }] },
  ];
  const r = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents,
      generationConfig: { temperature: 0.4, maxOutputTokens: 280 },
    }),
  });
  const data = await r.json();
  if (!r.ok) {
    console.error('Gemini help', r.status, data);
    return null;
  }
  const text =
    data?.candidates?.[0]?.content?.parts?.map((p) => p.text).join('') || '';
  return String(text).trim() || null;
}

/**
 * Agente de ayuda in-app (Gemini + fallback local).
 * POST /agent/help { "message": "...", "sessionId"?: "..." }
 */
app.post('/agent/help', async (req, res) => {
  const message = String(req.body?.message || '').trim();
  if (!message) return res.status(400).json({ error: 'message requerido' });
  const sessionId = String(req.body?.sessionId || randomUUID()).trim();
  if (!helpSessions.has(sessionId)) helpSessions.set(sessionId, []);
  const history = helpSessions.get(sessionId);

  let reply = null;
  let source = 'local';
  try {
    reply = await geminiHelp(history, message);
    if (reply) source = 'gemini';
  } catch (e) {
    console.error('help agent', e);
  }
  if (!reply) {
    reply = helpLocalReply(message);
    source = 'local';
  }

  history.push({ role: 'user', text: message });
  history.push({ role: 'assistant', text: reply });
  if (history.length > 24) history.splice(0, history.length - 24);

  return res.json({
    sessionId,
    reply,
    source,
    zavu: {
      configured: Boolean(process.env.ZAVU_API_KEY),
      whatsappNumber: process.env.ZAVU_WHATSAPP_NUMBER || '',
    },
  });
});

/**
 * Estado Zavu
 * GET /agent/zavu/status
 */
app.get('/agent/zavu/status', (_req, res) => {
  const number = String(process.env.ZAVU_WHATSAPP_NUMBER || '').replace(/\D/g, '');
  res.json({
    configured: Boolean(process.env.ZAVU_API_KEY),
    senderId: Boolean(process.env.ZAVU_SENDER_ID),
    whatsappNumber: number,
    waMe: number ? `https://wa.me/${number}` : '',
    docs: 'https://www.zavu.dev/es',
  });
});

/**
 * Enviar mensaje vía Zavu (WhatsApp/SMS routing).
 * POST /agent/zavu/send { "to": "+591...", "text": "..." }
 * Docs: https://www.zavu.dev/es
 */
app.post('/agent/zavu/send', async (req, res) => {
  const apiKey = process.env.ZAVU_API_KEY;
  if (!apiKey) {
    return res.status(503).json({
      error: 'ZAVU_API_KEY no configurada en Render',
      docs: 'https://www.zavu.dev/es',
    });
  }
  const to = String(req.body?.to || '').trim();
  const text = String(req.body?.text || '').trim();
  if (!to || !text) {
    return res.status(400).json({ error: 'to y text requeridos' });
  }

  const body = { to, text };
  if (process.env.ZAVU_SENDER_ID) {
    body.from = process.env.ZAVU_SENDER_ID;
  }

  try {
    const r = await fetch('https://api.zavu.dev/v1/messages', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) {
      console.error('Zavu send', r.status, data);
      return res.status(502).json({
        error: 'Zavu no pudo enviar',
        detail: data,
        docs: 'https://docs.zavu.dev',
      });
    }
    return res.json({ ok: true, provider: 'zavu', data });
  } catch (e) {
    console.error('Zavu', e);
    return res.status(500).json({ error: String(e.message || e) });
  }
});

/** roomId -> Map(userId -> { ws, role, joinedAt }) */
const rooms = new Map();

/** Invites pendientes: toUserId -> { fromUserId, fromName, roomId, at } */
const pendingInvites = new Map();
const PENDING_TTL_MS = 60_000;

function storePendingInvite(toUserId, invite) {
  pendingInvites.set(toUserId, { ...invite, at: Date.now() });
  // Limpieza automática
  setTimeout(() => {
    const cur = pendingInvites.get(toUserId);
    if (cur && cur.roomId === invite.roomId && Date.now() - cur.at >= PENDING_TTL_MS) {
      pendingInvites.delete(toUserId);
    }
  }, PENDING_TTL_MS + 500);
}

function deliverInvite(toUserId, envelope) {
  const target = `lobby:${toUserId}`;
  const lobby = rooms.get(target);
  let delivered = 0;
  if (lobby) {
    const raw = JSON.stringify(envelope);
    for (const client of lobby.values()) {
      if (client.ws.readyState === 1) {
        client.ws.send(raw);
        delivered++;
      }
    }
  }
  // Guardar siempre: si el lobby se conecta 1 s después, lo recibe al join
  storePendingInvite(toUserId, {
    fromUserId: envelope.fromUserId,
    fromName: envelope.fromName,
    roomId: envelope.roomId,
    callRoomId: envelope.callRoomId || envelope.roomId,
  });
  return delivered;
}

function flushPendingInvite(toUserId, ws) {
  const pending = pendingInvites.get(toUserId);
  if (!pending) return;
  if (Date.now() - pending.at > PENDING_TTL_MS) {
    pendingInvites.delete(toUserId);
    return;
  }
  try {
    ws.send(
      JSON.stringify({
        type: 'invite',
        fromUserId: pending.fromUserId,
        fromName: pending.fromName,
        roomId: pending.roomId,
        callRoomId: pending.callRoomId || pending.roomId,
        at: new Date().toISOString(),
        pending: true,
      }),
    );
  } catch (_) {}
}

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

/** HTTP: avisar llamada aunque el WS del llamante aún no esté listo */
app.post('/call/invite', (req, res) => {
  try {
    const toUserId = String(req.body?.toUserId || '').trim();
    const fromUserId = String(req.body?.fromUserId || '').trim();
    const fromName = String(req.body?.fromName || 'Contacto').trim();
    const roomId = String(req.body?.roomId || req.body?.callRoomId || '').trim();
    if (!toUserId || !fromUserId || !roomId) {
      return res.status(400).json({ error: 'toUserId, fromUserId y roomId requeridos' });
    }
    const envelope = {
      type: 'invite',
      fromUserId,
      fromName,
      roomId,
      callRoomId: roomId,
      at: new Date().toISOString(),
    };
    const delivered = deliverInvite(toUserId, envelope);
    return res.json({
      ok: true,
      delivered,
      pending: true,
      lobbyOnline: delivered > 0,
    });
  } catch (e) {
    return res.status(500).json({ error: String(e.message || e) });
  }
});

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

      // Si hay una llamada pendiente para este lobby, entregarla ya
      if (roomId.startsWith('lobby:')) {
        flushPendingInvite(userId, ws);
      }

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

    // Frame de video (JPEG base64) → el otro ve la cámara en vivo
    if (type === 'frame') {
      const roomId = String(msg.roomId || meta.roomId || '').trim();
      const userId = String(msg.userId || meta.userId || '').trim();
      const data = String(msg.data || '').trim();
      if (!roomId || !userId || !data || data.length > 120000) return;

      broadcast(
        roomId,
        {
          type: 'frame',
          roomId,
          userId,
          data,
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
      const toUserId = String(msg.toUserId || '').trim();
      const target =
        String(msg.targetLobby || '').trim() ||
        (toUserId ? `lobby:${toUserId}` : '');
      const fromUserId = String(msg.fromUserId || msg.userId || meta.userId || '').trim();
      const roomId = String(msg.callRoomId || msg.roomId || '').trim();
      const fromName = String(msg.fromName || 'Contacto').trim();
      const destUser =
        toUserId ||
        (target.startsWith('lobby:') ? target.slice('lobby:'.length) : '');
      if (!destUser || !fromUserId || !roomId) return;

      deliverInvite(destUser, {
        type: 'invite',
        fromUserId,
        fromName,
        roomId,
        callRoomId: roomId,
        toUserId: destUser,
        at: new Date().toISOString(),
      });
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
