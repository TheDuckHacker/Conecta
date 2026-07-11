# Quickstart: Conecta LSB

> Base del README del repo público (entregable obligatorio del buildathon).

## Requisitos

- Node.js 20+
- Chrome (desktop para desarrollo, Android para la demo)
- Cámara y micrófono

## Ejecutar en desarrollo

```bash
npm install
npm run dev
# abrir http://localhost:5173
```

Para probar en el teléfono (la cámara requiere HTTPS fuera de localhost):

```bash
npm run dev -- --host   # + túnel HTTPS (ngrok/cloudflared) o usar el deploy
```

## Flujo de demo (P1)

1. Abrir la app → **Iniciar conversación**.
2. Persona sorda: hacer una seña del vocabulario frente a la cámara → aparece el
   texto en español y se reproduce en voz.
3. Persona oyente: tocar el micrófono y hablar → aparece la transcripción en
   pantalla.
4. Repetir por turnos; el historial muestra emisor y canal de cada mensaje.

## Grabar muestras del vocabulario

```bash
npm run record-samples   # etiqueta y guarda landmarks por glosa en src/vision/vocab.json
```

## Verificar el clasificador

```bash
npm run check-classifier # precisión contra las muestras reservadas; objetivo ≥ 80%
```

## Deploy

Push a `main` → deploy automático en Vercel (URL pública para los jueces).
