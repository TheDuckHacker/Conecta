import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** Raíz del monorepo Conecta (tools/cursor-agent/src → ../../..) */
export const REPO_ROOT = path.resolve(__dirname, "../../..");

export function requireApiKey(): string {
  const key = process.env.CURSOR_API_KEY?.trim();
  if (!key) {
    throw new Error(
      "Falta CURSOR_API_KEY. Cópiala en https://cursor.com/dashboard/integrations",
    );
  }
  return key;
}

export function modelId(): string {
  return process.env.CURSOR_MODEL?.trim() || "composer-2.5";
}

export function useCloud(): boolean {
  return Boolean(process.env.CURSOR_CLOUD_REPO?.trim());
}

export function cloudRepos() {
  const url = process.env.CURSOR_CLOUD_REPO!.trim();
  const startingRef = process.env.CURSOR_CLOUD_REF?.trim() || "main";
  return [{ url, startingRef }];
}
