# Diseño UI: Conecta Videollamada (estilo WhatsApp)

> Diseño de interfaz para una app de videollamadas accesible, inspirada en WhatsApp, pero adaptada para comunicación entre persona sorda (LSB) y persona oyente.

## 1. Estructura de pantallas

La app tiene **4 pestañas principales** en la barra inferior, tipo WhatsApp:

| Pestaña | Icono | Función |
|---------|-------|---------|
| **Chats** | 💬 | Historial de llamadas y conversaciones recientes |
| **Llamadas** | 📹 | Lista de contactos disponibles para videollamada |
| **Aprender** | 🎓 | Lecciones de LSB |
| **Configuración** | ⚙️ | Perfil, accesibilidad, idioma |

---

## 2. Pantalla 1: Lista de llamadas / Contactos

> Similar a la pestaña "Llamadas" de WhatsApp.

**AppBar:**
- Título: **"Conecta"**
- Acciones derecha: 🔍 buscar, ⋮ menú (configuración, ayuda)

**Floating Action Button (FAB):**
- ➕ azul, redondo, grande.
- Al tocar: abre pantalla para iniciar videollamada (elegir contacto o ingresar código).

**Lista de items:**
Cada item muestra:
- Foto/avatar circular a la izquierda.
- Nombre del contacto en negrita.
- Subtítulo: estado de la última llamada ("Videollamada entrante", "Videollamada perdida", "Duración 5:23").
- Icono de tipo: 📹 video o 📞 audio.
- Fecha/hora a la derecha.

**Ejemplo de item:**
```
[👤] Juan Pérez
     📹 Videollamada saliente              14:30
     Duración 3:45
```

---

## 3. Pantalla 2: Iniciar videollamada

> Similar a seleccionar contacto en WhatsApp antes de llamar.

**AppBar:**
- Título: **"Nueva videollamada"**
- Campo de búsqueda opcional.

**Opciones:**
- Campo de texto: **"Ingresar código de sala"** (4-6 dígitos).
- Botón grande: **"Crear sala"** (genera código para compartir).
- Lista de contactos frecuentes debajo.

---

## 4. Pantalla 3: Videollamada en curso

> Pantalla principal. Similar a WhatsApp/Meet pero con subtítulos accesibles.

### Layout general

```
┌─────────────────────────────┐
│  [Video remoto grande]      │
│                             │
│  [Subtítulos aquí]          │
│  "Hola, ¿cómo estás?"       │
│                             │
│  ┌─────────────────────┐    │
│  │ [Video propio]      │    │
│  │ (picture-in-picture)│    │
│  └─────────────────────┘    │
│                             │
│  [Indicador de señas]       │
│  "Reconociendo manos..."    │
│                             │
│  [ 🔇 ] [ 📹 ] [ 📞 ]       │
│  [ 📝 ] [ ↔️ ] [ ⚙️ ]       │
└─────────────────────────────┘
```

### Elementos

**Video remoto (pantalla completa):**
- Ocupa todo el fondo.
- Si el otro no activa cámara, muestra avatar grande con nombre.

**Video propio (picture-in-picture):**
- Esquina superior derecha, tamaño ~120 x 160 dp, bordes redondeados.
- Puede arrastrarse a otra esquina.

**Subtítulos / Traducción (zona central inferior):**
- Caja oscura semitransparente (fondo negro 70%, texto blanco).
- Muestra el último mensaje traducido.
- Indica el emisor: "Tú: Hola" / "Juan: Buenas tardes".
- Si la seña no se entiende: "No entendí, repite por favor".

**Indicador de reconocimiento de señas:**
- Barra pequeña arriba de los botones.
- Estados:
  - 🔴 "No se detectan manos"
  - 🟡 "Detectando..."
  - 🟢 "Seña reconocida: HOLA"

**Botones de control (fila inferior):**

| Botón | Icono | Acción |
|-------|-------|--------|
| Silenciar micrófono | 🎤 (tachado) | Apagar/encender micrófono del oyente |
| Apagar cámara | 📹 (tachada) | Apagar/encender cámara |
| Colgar | 📞 rojo grande | Terminar llamada |
| Abrir chat de texto | 💬 | Mostrar teclado para escribir mensaje |
| Cambiar cámara | 🔄 | Frontal / trasera |
| Más opciones | ⋮ | Audio, calidad, subtítulos grandes |

**Barra superior durante la llamada:**
- Nombre del contacto.
- Duración de la llamada (00:34).
- Indicador de calidad de red: 📶 (verde/amarillo/rojo).
- Botón para minimizar llamada.

---

## 5. Pantalla 4: Chat de texto durante la llamada

> Se desliza desde abajo, como un panel inferior.

**Componentes:**
- Lista de mensajes de texto enviados durante la llamada.
- Campo de texto en la parte inferior.
- Botón de enviar (▶️).
- Botón de mensajes rápidos: "Sí", "No", "Gracias", "Repite".

---

## 6. Pantalla 5: Llamada entrante

> Pantalla a pantalla completa.

```
┌─────────────────────────────┐
│                             │
│        [Avatar grande]      │
│                             │
│      Juan Pérez             │
│   Videollamada entrante     │
│                             │
│                             │
│   [🎤]              [📹]    │
│  Rechazar          Contestar│
│  (rojo)              (azul) │
│                             │
└─────────────────────────────┘
```

**Botones:**
- Rechazar llamada: botón circular rojo con 📞 hacia abajo.
- Contestar: botón circular azul con 📹.

---

## 7. Pantalla 6: Aprender LSB

> Lista de lecciones tipo catálogo.

**AppBar:**
- Título: **"Aprender LSB"**

**Lista de lecciones:**
- Tarjetas con:
  - Imagen miniatura de una seña.
  - Título: "Saludos básicos".
  - Progreso: barra de 3/5.
  - Botón **"Continuar"** o **"Empezar"**.

---

## 8. Paleta de colores (accesible)

| Elemento | Color | Hex |
|----------|-------|-----|
| Fondo general | Blanco/gris muy claro | `#FFFFFF` / `#F0F4F8` |
| Primario (acento) | Azul Conecta | `#2563EB` |
| Colgar / Error | Rojo coral | `#EF4444` |
| Botón de acción secundaria | Azul claro | `#60A5FA` |
| Subtítulos (fondo) | Negro semitransparente | `#CC000000` |
| Texto subtítulos | Blanco | `#FFFFFF` |
| Indicador éxito | Verde azulado | `#10B981` |
| Indicador advertencia | Ámbar | `#F59E0B` |
| Indicador error | Rojo | `#EF4444` |
| FAB / llamar | Azul principal | `#2563EB` |
| Barra superior (AppBar) | Azul oscuro | `#1E40AF` |
| Botón contestar llamada | Azul brillante | `#3B82F6` |
| Botón rechazar llamada | Rojo coral | `#EF4444` |

---

## 9. Tipografía y accesibilidad

- Fuente: **Roboto** o **Inter**.
- Tamaño de subtítulos: **22-26 sp** (muy legible).
- Nombres y duración: **16-18 sp**.
- Botones: iconos de **28 dp** mínimo.
- Área de toque: **56 x 56 dp** mínimo.
- **Sin depender del sonido**: vibración al recibir llamada, flashes de pantalla, notificaciones visuales grandes.
- **Contraste alto**: textos sobre fondos oscuros, botones con bordes.

---

## 10. Flujo de usuario resumido

```
Abrir app
   │
   ▼
Pestaña Llamadas
   │
   ├── Crear sala ──► Compartir código
   │
   └── Ingresar código ──► Conectar
              │
              ▼
      Pantalla de videollamada
              │
   ┌──────────┼──────────┐
   ▼          ▼          ▼
 Subtítulos  Chat texto  Colgar
 (LSB↔ES)    (respaldo)
```

---

## 11. Notas para el diseñador / Figma

- Usar frames de **375 × 812 dp** (iPhone/Android estándar).
- Crear variantes para: llamada activa, llamada entrante, sin cámara del otro, chat de texto abierto, reconociendo seña.
- Incluir modo oscuro opcional.
- Los subtítulos deben ser prominentes, ya que son el canal principal de comunicación.
- El botón de colgar siempre visible y grande, incluso con el chat abierto.
