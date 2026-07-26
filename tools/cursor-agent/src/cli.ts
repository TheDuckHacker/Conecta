#!/usr/bin/env node
import { loadDotEnv } from "./loadEnv.js";
import { fixPrompt, REVIEW_PROMPT } from "./prompts.js";
import { runPrompt, runStreaming } from "./run.js";

loadDotEnv();

const [cmd, ...rest] = process.argv.slice(2);

function usage(): never {
  console.error(`Uso:
  npm run prompt -- "tu instrucción"
  npm run review
  npm run fix -- "corrige X en Y"

Variables: CURSOR_API_KEY (obligatoria)
  CURSOR_CLOUD_REPO / CURSOR_CLOUD_REF  → runtime cloud
  CURSOR_AUTO_PR=1                      → abrir PR (solo cloud)
  STREAM=1                              → streaming en vez de one-shot
`);
  process.exit(1);
}

async function main() {
  if (!cmd) usage();

  const stream = process.env.STREAM === "1";
  let prompt: string;

  switch (cmd) {
    case "prompt": {
      prompt = rest.join(" ").trim();
      if (!prompt) usage();
      break;
    }
    case "review":
      prompt = REVIEW_PROMPT;
      break;
    case "fix": {
      const task = rest.join(" ").trim();
      if (!task) usage();
      prompt = fixPrompt(task);
      break;
    }
    default:
      usage();
  }

  if (stream) {
    await runStreaming(prompt);
    return;
  }

  const out = await runPrompt(prompt);
  if (out.result) console.log(out.result);
  if (out.runId) console.error(`[run] ${out.runId}`);
  console.error(`[status] ${out.status}`);
  if (out.status === "error") process.exitCode = 2;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
