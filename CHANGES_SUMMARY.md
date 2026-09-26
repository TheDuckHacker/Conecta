# Resumen de Cambios: Fix Realtime Server Issues

## Pull Request
[#1](https://github.com/TheDuckHacker/Conecta/pull/1) - Fix Conecta realtime server: Gemini robustness, honest health/zavu status, HTTP auth, catalog

## Problemas Identificados y Resueltos

### A) Gemini no funcionaba correctamente
**Problema:**
- POST /ai/compose retornaba `source: local` con `note: gemini_fallback` incluso con GEMINI_API_KEY configurada
- Modelo `gemini-flash-latest` probablemente inválido
- Latencia de ~4-7s sin usar IA

**Solución:**
- ✅ Modelo por defecto cambiado a `gemini-2.0-flash-exp` (conocido y estable)
- ✅ Fallback automático a `gemini-1.5-flash` si el primero falla con error de modelo
- ✅ Variable `GEMINI_MODEL` para override manual
- ✅ Logs detallados sin exponer API keys
- ✅ Mismo patrón aplicado en `/agent/help`

### B) Health y Zavu status reportaban información engañosa
**Problema:**
- GET /health reportaba `ai: true`, `zavu: true` solo chequeando claves
- GET /agent/zavu/status reportaba `configured: true` con `senderId: false`
- Confusión sobre qué servicios estaban realmente listos

**Solución:**
- ✅ Health endpoint ahora retorna:
  - `aiConfigured: boolean` - GEMINI_API_KEY presente
  - `zavuKey: boolean` - ZAVU_API_KEY presente
  - `zavuReady: boolean` - key + sender (realmente listo para enviar)
- ✅ Zavu status ahora retorna:
  - `key`, `senderId`, `ready` (todos presentes = ready)
  - `configured` como alias de `ready` (backward compatible)

### C) Rutas HTTP sensibles estaban públicas
**Problema:**
- Sin autenticación en rutas sensibles: `/ai/compose`, `/tts`, `/agent/help`, `/agent/zavu/send`, `/call/invite`
- CORS `*` abierto
- Cualquiera podía consumir los servicios

**Solución:**
- ✅ Nueva variable `CONECTA_API_KEY` (opcional)
- ✅ Middleware `requireAuth()` que chequea `X-Conecta-Key` o `Authorization: Bearer`
- ✅ Cuando está configurada: rutas protegidas retornan 401 sin auth válida
- ✅ Cuando no está configurada: rutas abiertas con warning en startup (solo dev)
- ✅ GET /health y GET / quedan públicas
- ✅ Cliente Flutter actualizado para enviar el header en todas las llamadas HTTP

### D) Catálogo incompleto
**Problema:**
- GET / omitía `/call/invite`

**Solución:**
- ✅ GET / ahora incluye `'invite': '/call/invite'`

## Archivos Modificados

### Servidor (realtime-server/)
1. **server.js**
   - Middleware `requireAuth()` agregado
   - Health endpoint con campos honestos `aiConfigured`, `zavuKey`, `zavuReady`
   - Gemini con modelo robusto y fallback
   - Zavu status con campos `key`, `senderId`, `ready`
   - Todas las rutas sensibles protegidas con `requireAuth`
   - Catálogo completo en GET /

2. **README.md**
   - Documentación de todas las variables de entorno
   - Instrucciones de seguridad con `CONECTA_API_KEY`
   - Enlaces para obtener API keys
   - Sección clara sobre Zavu siendo opcional

3. **.env.example**
   - Estructura por secciones: Requeridas / Seguridad / Zavu opcional
   - Comentarios detallados con URLs
   - Ejemplo de `CONECTA_API_KEY`

### Cliente Flutter (lib/services/)
1. **ai_config.dart**
   - Nuevo getter `headers` que incluye `X-Conecta-Key` cuando está definida
   - Soporte para `--dart-define=CONECTA_API_KEY`

2. **sign_ai_agent.dart**
   - Actualizado para usar `AiConfig.headers`

3. **help_agent_service.dart**
   - Actualizado para usar `AiConfig.headers` en todas las llamadas

4. **call_service.dart**
   - Import de `ai_config.dart` agregado
   - `postInviteHttp()` actualizado para usar `AiConfig.headers`

5. **voice_bridge_service.dart**
   - `_speakViaRender()` actualizado para usar `AiConfig.headers`

### Documentación
1. **README.md** (raíz)
   - Nueva sección "Desarrollo y Construcción"
   - Instrucciones de build con `--dart-define`

## Testing Realizado

✅ Server arranca sin `CONECTA_API_KEY` (warning apropiado)
✅ Server arranca con `CONECTA_API_KEY` (mensaje de confirmación)
✅ Rutas públicas accesibles sin auth (/, /health)
✅ Rutas protegidas retornan 401 sin auth
✅ Rutas protegidas funcionan con auth correcta
✅ Health endpoint retorna campos correctos
✅ Catálogo incluye /call/invite
✅ Sintaxis JavaScript válida
✅ Código Dart válido

## Configuración en Render

Para aprovechar estos cambios en producción:

1. **Configurar en Render → Environment:**
   ```
   GEMINI_API_KEY=<tu-clave-de-google-ai-studio>
   GEMINI_MODEL=gemini-2.0-flash-exp (opcional)
   CONECTA_API_KEY=<genera-una-clave-segura>
   ELEVENLABS_API_KEY=<tu-clave-elevenlabs> (opcional)
   ```

2. **Configurar en Flutter build:**
   ```bash
   flutter build apk --dart-define=CONECTA_API_KEY=<misma-clave-que-render>
   ```

## Backward Compatibility

- ✅ Cliente Flutter antiguo puede seguir funcionando si `CONECTA_API_KEY` no está configurada en Render (modo dev)
- ✅ Health endpoint mantiene campos legacy donde tiene sentido
- ✅ Zavu status mantiene `configured` como alias de `ready`

## Próximos Pasos (Fuera del Scope)

- WebSocket auth (requiere más plumbing en cliente)
- Rate limiting por IP/key
- Métricas de uso por endpoint
