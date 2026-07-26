import { Agent, CursorAgentError } from "@cursor/sdk";
import {
  cloudRepos,
  modelId,
  REPO_ROOT,
  requireApiKey,
  useCloud,
} from "./config.js";

export type RunMode = "local" | "cloud";

function agentOptions() {
  const apiKey = requireApiKey();
  const model = { id: modelId() };
  if (useCloud()) {
    return {
      apiKey,
      model,
      cloud: {
        repos: cloudRepos(),
        autoCreatePR: process.env.CURSOR_AUTO_PR === "1",
        skipReviewerRequest: true,
      },
    };
  }
  return {
    apiKey,
    model,
    local: {
      cwd: REPO_ROOT,
      // Solo config inline; no cargar settings del IDE
      settingSources: [],
    },
  };
}

/** One-shot: crea, ejecuta, dispone. */
export async function runPrompt(prompt: string): Promise<{
  status: string;
  result?: string;
  runId?: string;
}> {
  try {
    const result = await Agent.prompt(prompt, agentOptions());
    return {
      status: result.status,
      result: result.result,
      runId: result.id,
    };
  } catch (err) {
    if (err instanceof CursorAgentError) {
      console.error(
        `Arranque fallido: ${err.message} (retryable=${err.isRetryable})`,
      );
      process.exitCode = 1;
      return { status: "startup_error" };
    }
    throw err;
  }
}

/** Streaming multi-turno con dispose limpio. */
export async function runStreaming(prompt: string): Promise<void> {
  await using agent = await Agent.create(agentOptions());
  console.error(`[agent] ${agent.agentId} · ${useCloud() ? "cloud" : "local"}`);

  const run = await agent.send(prompt);
  console.error(`[run] ${run.id}`);

  for await (const event of run.stream()) {
    if (event.type === "assistant") {
      for (const block of event.message.content) {
        if (block.type === "text") process.stdout.write(block.text);
      }
    }
  }

  const result = await run.wait();
  process.stdout.write("\n");
  if (result.status === "error") {
    console.error(`[error] run ${result.id}`);
    process.exitCode = 2;
  } else {
    console.error(`[done] ${result.status}`);
  }
}
