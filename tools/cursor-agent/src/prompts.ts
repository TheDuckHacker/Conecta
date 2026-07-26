/** Prompts listos para el repo Conecta LSB. */

export const REVIEW_PROMPT = `Eres el agente de desarrollo de Conecta LSB (Flutter + Appwrite + realtime-server Node).

Revisa el repositorio y entrega un informe breve en español con:
1. Riesgos / bugs evidentes en lib/services (auth, llamadas, detección de señas, agente IA).
2. Problemas en realtime-server/server.js (compose, TTS, WebSocket).
3. 3 mejoras concretas priorizadas (archivos + cambio sugerido).

No edites archivos en este modo; solo analiza y reporta.`;

export function fixPrompt(task: string): string {
  return `Eres el agente de desarrollo de Conecta LSB (Flutter + Appwrite + Node realtime).

Tarea: ${task}

Reglas:
- Cambia solo lo necesario para completar la tarea.
- Mantén el estilo del código existente.
- No commits ni push.
- Al final, lista archivos tocados y cómo probar.`;
}
