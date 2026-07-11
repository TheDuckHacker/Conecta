# Conecta Constitution

> Conecta (Conecta LSB): plataforma de comunicación accesible para personas sordas
> mediante Lengua de Señas Boliviana (LSB). Proyecto para el Cursor Buildathon
> Bolivia 2026 — Track Social Impact AI.

## Core Principles

### I. Adopción real sobre complejidad técnica
El track Social Impact AI prioriza "el problema local y la adopción real" sobre
la sofisticación técnica. Cada decisión de producto se evalúa con la pregunta:
¿una persona sorda en Santa Cruz lo usaría mañana? Se descarta cualquier
funcionalidad que no acerque al usuario objetivo (personas sordas, sus familias
e instituciones que necesitan comunicación accesible).

### II. Demo en vivo primero (NON-NEGOTIABLE)
Todo lo que se construya debe poder demostrarse en vivo en 4 minutos el Demo Day
(26/7/2026, deadline 8:30 AM). Una funcionalidad que no se puede demostrar en
vivo no existe. El flujo de demo (llamada con traducción doble canal) se prueba
de punta a punta cada vez que se integra algo nuevo.

### III. Alcance mínimo viable por prioridad
Las historias de usuario se implementan en orden estricto de prioridad (P1 → P2
→ P3). No se empieza una historia de menor prioridad si la anterior no está
demostrable. YAGNI: los idiomas regionales (guaraní, quechua, aymara) y la
plataforma de aprendizaje son evolución post-hackathon, no alcance del evento.

### IV. Accesibilidad como requisito, no como feature
La app está pensada para personas sordas: toda información sonora tiene
equivalente visual (texto, señas, vibración), la UI funciona sin audio, y los
textos usan lenguaje claro. Esto no se recorta bajo presión de tiempo.

### V. IA con uso central y significativo
Regla del evento: el proyecto debe usar IA de forma central. En Conecta la IA es
el producto: reconocimiento de señas por cámara, voz a texto y texto/voz como
canal doble de traducción. Se usan modelos y APIs existentes antes que entrenar
desde cero; el valor está en la integración y la experiencia, no en reinventar
modelos.

## Restricciones del evento

- Código iniciado durante la hackathon (25–26/7/2026); solo boilerplate previo,
  documentado. Esta documentación/especificación es preparación permitida.
- Repositorio público con README (problema, solución, stack, instrucciones).
- Librerías open-source, APIs y SDKs de sponsors permitidos y documentados.
- Equipo de 2 a 4 personas; al menos un miembro presente en Demo Day.
- Rúbrica: claridad del problema 20%, ejecución técnica 25%, uso significativo
  de IA 20%, calidad de demo/UX 15%, potencial real y originalidad 20%.

## Flujo de trabajo

- Spec-kit gobierna la documentación: spec.md → plan.md → tasks.md antes de
  codificar cada feature.
- Commits pequeños y frecuentes durante el evento; el repo debe quedar
  ejecutable con las instrucciones del README en cualquier momento.
- Prueba manual del flujo de demo tras cada integración; sin frameworks de
  test pesados durante las 24 horas.

## Governance

Esta constitución prevalece sobre cualquier otra práctica del proyecto. Toda
adición de alcance se contrasta contra los Principios I–III; si no ayuda a la
demo o a la adopción real, se pospone a post-hackathon. Enmiendas se documentan
en este archivo con nueva versión y fecha.

**Version**: 1.0.0 | **Ratified**: 2026-07-11 | **Last Amended**: 2026-07-11
