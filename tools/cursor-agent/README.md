# Conecta · Cursor Agent (desarrollo)

Agente de código sobre el repo Conecta usando [`@cursor/sdk`](https://cursor.com/docs/sdk/typescript).

## Setup

```bash
cd tools/cursor-agent
npm install
cp .env.example .env   # o export CURSOR_API_KEY=...
```

Clave: [Dashboard → Integrations](https://cursor.com/dashboard/integrations). Requiere **Node ≥ 22.13**.

## Comandos

```bash
# Instrucción libre (local, cwd = raíz del repo)
npm run prompt -- "Resume la arquitectura de realtime-server"

# Informe de riesgos / mejoras (sin editar)
npm run review

# Pedir cambios en el código
npm run fix -- "Mejora el debounce del agente de señas en sign_ai_agent.dart"

# Streaming en vivo
STREAM=1 npm run prompt -- "Lista los endpoints HTTP del servidor"
```

## Cloud (opcional)

```bash
export CURSOR_CLOUD_REPO=https://github.com/TU_ORG/Conecta
export CURSOR_CLOUD_REF=main
export CURSOR_AUTO_PR=1   # abrir PR al terminar
npm run fix -- "..."
```

Sin `CURSOR_CLOUD_REPO` corre en **local** (archivos de tu máquina).
