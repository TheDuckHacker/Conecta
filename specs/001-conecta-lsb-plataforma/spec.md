# Feature Specification: Conecta LSB — Comunicación accesible con traducción doble canal

**Feature Branch**: `001-conecta-lsb-plataforma`

**Created**: 2026-07-11

**Status**: Draft

**Input**: User description: "Conecta LSB - plataforma de comunicación accesible por llamada con traducción doble canal entre Lengua de Señas Boliviana y español"

## Contexto

**Problema**: En Bolivia, las personas sordas que se comunican en Lengua de Señas
Boliviana (LSB) quedan excluidas de conversaciones cotidianas con personas
oyentes que no conocen señas: trámites en instituciones, consultas médicas,
comunicación con familiares. Los intérpretes humanos son escasos y costosos.

**Solución**: App móvil que actúa como intérprete en vivo con **traducción doble
canal**: la cámara traduce las señas de la persona sorda a texto/voz para la
persona oyente, y el micrófono traduce la voz de la persona oyente a texto para
la persona sorda. Además, un módulo de aprendizaje visual de LSB con validación
en vivo por cámara.

**Público objetivo**:
- Personas sordas y sordomudas usuarias de LSB (usuario primario).
- Personas oyentes que necesitan comunicarse con ellas: familiares, funcionarios
  de instituciones, personal de salud (usuario secundario).
- Personas que quieren aprender LSB.
- Instituciones que necesitan comunicación accesible; aliados potenciales:
  Federación Boliviana de Sordos (FEBOS), Ministerio de Educación — Dirección
  General de Educación Especial.

**Alcance geográfico inicial**: Santa Cruz de la Sierra, Bolivia. Evolución
futura: traducción a lenguas regionales (guaraní, quechua, aymara).

**Evento**: Cursor Buildathon Bolivia 2026 (25–26 julio), Track Social Impact AI.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Conversación presencial con traducción doble canal (Priority: P1)

Una persona sorda y una persona oyente están frente a frente (p. ej., en una
ventanilla de un banco). Abren Conecta en un teléfono. La persona sorda hace
señas frente a la cámara y la app las traduce a texto y voz en español para la
persona oyente. La persona oyente habla y la app transcribe su voz a texto en
pantalla para la persona sorda. La conversación fluye por turnos en una misma
pantalla dividida.

**Why this priority**: Es el núcleo del producto y de la demo: sin traducción
doble canal no hay Conecta. Funciona con un solo dispositivo, lo que minimiza
riesgo técnico en la demo y refleja el caso de uso más frecuente (trámites,
atención presencial).

**Independent Test**: Con un solo teléfono, una persona hace 5 señas del
vocabulario soportado y otra responde hablando; se verifica que ambas partes
reciben la traducción correcta en pantalla.

**Acceptance Scenarios**:

1. **Given** la app está en modo conversación con cámara activa, **When** la
   persona sorda realiza una seña del vocabulario soportado, **Then** la app
   muestra el texto en español y lo reproduce en voz alta en menos de 3 segundos.
2. **Given** la app está en modo conversación con micrófono activo, **When** la
   persona oyente habla en español, **Then** la app muestra la transcripción en
   texto legible para la persona sorda en menos de 3 segundos.
3. **Given** una seña no reconocida o con baja confianza, **When** la app no
   puede traducirla, **Then** indica visualmente "no entendí, repite por favor"
   en lugar de mostrar una traducción incorrecta.
4. **Given** una conversación en curso, **When** cualquiera de las partes revisa
   la pantalla, **Then** ve el historial de la conversación con cada mensaje
   identificado por emisor y canal (señas o voz).

---

### User Story 2 - Llamada remota con traducción en vivo (Priority: P2)

Una persona sorda llama por video a un familiar oyente que está en otro lugar.
Durante la videollamada, Conecta traduce en vivo las señas a voz/texto para el
oyente y la voz del oyente a texto para la persona sorda, en ambos dispositivos.

**Why this priority**: Es el diferenciador del pitch ("plataforma de comunicación
por llamada"), pero depende de que el motor de traducción (P1) funcione y agrega
riesgo de infraestructura (video en tiempo real). Se construye sobre P1.

**Independent Test**: Dos teléfonos en la misma red realizan una llamada; se
verifica que las señas de un extremo llegan como texto/voz al otro y viceversa.

**Acceptance Scenarios**:

1. **Given** dos usuarios conectados en una llamada, **When** la persona sorda
   hace una seña soportada, **Then** el dispositivo del oyente muestra el texto
   y reproduce la voz correspondiente.
2. **Given** una llamada activa, **When** el oyente habla, **Then** la persona
   sorda ve la transcripción en su pantalla sobre el video.
3. **Given** una conexión inestable, **When** el video se degrada, **Then** el
   canal de texto sigue funcionando como respaldo de la conversación.

---

### User Story 3 - Aprendizaje visual de LSB con validación en vivo (Priority: P3)

Una persona oyente (familiar, funcionario o interesado) quiere aprender señas
básicas de LSB. Entra al módulo de aprendizaje, ve una guía visual de cada seña,
la practica frente a la cámara y la app le confirma en vivo si la ejecutó
correctamente.

**Why this priority**: Amplía el impacto social (más gente aprende LSB) y
reutiliza el mismo motor de reconocimiento de P1, pero no es indispensable para
la demo de comunicación. Es la vía natural de crecimiento post-hackathon.

**Independent Test**: Un usuario sin conocimiento de LSB completa una lección de
5 señas y la app valida al menos sus intentos correctos e incorrectos de forma
consistente.

**Acceptance Scenarios**:

1. **Given** una lección seleccionada, **When** el usuario ve una seña de la
   guía, **Then** puede reproducir la demostración visual las veces que quiera.
2. **Given** la práctica con cámara activa, **When** el usuario ejecuta la seña
   correctamente, **Then** la app lo confirma visualmente y avanza a la
   siguiente seña.
3. **Given** la práctica con cámara activa, **When** el usuario ejecuta la seña
   incorrectamente, **Then** la app se lo indica y le permite reintentar.

---

### Edge Cases

- **Iluminación pobre o cámara de baja calidad**: la app debe indicar cuando no
  puede ver bien las manos (guía de encuadre) en lugar de traducir mal.
- **Ruido de fondo**: la transcripción de voz debe seguir siendo utilizable en
  ambientes ruidosos típicos (calle, oficina pública); si no, indicar al oyente
  que repita.
- **Seña fuera del vocabulario soportado**: respuesta explícita de "no
  reconocido", nunca una traducción inventada.
- **Varias personas u objetos en el encuadre**: el reconocimiento se centra en
  la persona más prominente frente a la cámara.
- **Sin conexión o conexión intermitente**: la app comunica claramente qué
  funciones requieren internet; la conversación presencial degrada a
  texto escrito como último recurso.
- **Variaciones regionales de señas**: el vocabulario inicial se limita a señas
  LSB validadas; las variantes se registran como trabajo futuro.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema MUST reconocer señas de LSB desde la cámara y
  traducirlas a texto en español dentro del vocabulario soportado.
- **FR-002**: El sistema MUST convertir el texto traducido a voz en español
  (texto a voz) para la persona oyente.
- **FR-003**: El sistema MUST transcribir voz en español a texto en pantalla
  (voz a texto) para la persona sorda.
- **FR-004**: El sistema MUST presentar ambos canales en una vista de
  conversación con historial identificando emisor y canal.
- **FR-005**: El sistema MUST indicar explícitamente cuando una seña o audio no
  se pudo reconocer con confianza suficiente.
- **FR-006**: El sistema MUST funcionar en un teléfono móvil de gama media como
  experiencia principal.
- **FR-007**: El sistema SHOULD permitir llamadas remotas entre dos dispositivos
  con la traducción doble canal activa (P2).
- **FR-008**: El sistema SHOULD ofrecer lecciones de aprendizaje de LSB con
  demostración visual y validación por cámara (P3).
- **FR-009**: El sistema MUST ofrecer entrada de texto escrito como canal de
  respaldo para cualquiera de las partes.
- **FR-010**: El vocabulario LSB soportado para la demo MUST cubrir un conjunto
  útil para un escenario real (saludos, cortesía, necesidades básicas,
  emergencia) — mínimo 20 señas.

### Key Entities

- **Usuario**: persona que usa la app; perfil de comunicación preferido (señas /
  voz / texto). Sin registro obligatorio para la demo.
- **Conversación**: sesión de comunicación (presencial o llamada) entre dos
  partes; contiene mensajes ordenados.
- **Mensaje**: unidad traducida; atributos: emisor, canal de origen (seña, voz,
  texto), contenido original, traducción, confianza del reconocimiento.
- **Seña**: elemento del vocabulario LSB soportado; atributos: glosa (palabra),
  demostración visual, categoría (saludo, necesidad, emergencia).
- **Lección** (P3): secuencia ordenada de señas con guía y práctica validada.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Una seña soportada se traduce y vocaliza en menos de 3 segundos
  de punta a punta.
- **SC-002**: El reconocimiento de señas acierta al menos 8 de cada 10
  ejecuciones del vocabulario soportado en condiciones de demo (buena luz,
  encuadre correcto).
- **SC-003**: Una conversación de 6 turnos alternados (3 señas, 3 respuestas de
  voz) se completa sin intervención técnica.
- **SC-004**: El flujo completo de demo (abrir app → conversación doble canal →
  cierre) se ejecuta en vivo en menos de 4 minutos.
- **SC-005**: Una persona sin entrenamiento previo entiende cómo usar la vista
  de conversación en menos de 1 minuto (probado con al menos 2 personas ajenas
  al equipo durante el evento).
- **SC-006**: El repositorio público con README permite a un tercero ejecutar la
  demo siguiendo solo las instrucciones escritas.

## Assumptions

- El equipo (2–4 personas) incluye al menos un integrante con experiencia en
  agentes/IA y dispone de teléfonos Android para pruebas.
- Existen modelos/APIs de detección de manos-pose y de voz a texto utilizables
  como base; el reconocimiento de LSB se construye sobre ellos con un
  vocabulario limitado, no se entrena un modelo desde cero durante el evento.
- No existe un dataset público completo de LSB; el vocabulario de demo se
  captura/valida con material propio o de referencia de FEBOS.
- La demo dispondrá de internet compartido del evento; las funciones críticas
  de P1 deben tolerar ancho de banda limitado.
- Traducción a guaraní, quechua y aymara, monetización y despliegue en tiendas
  quedan explícitamente fuera del alcance de la hackathon.
- El código se inicia durante el evento; este repositorio contiene solo
  documentación y especificación (preparación permitida por las reglas).
