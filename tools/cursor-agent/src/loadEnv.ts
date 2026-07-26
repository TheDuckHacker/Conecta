import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** Carga tools/cursor-agent/.env si existe (sin dependencia extra). */
export function loadDotEnv(): void {
  const dir = path.dirname(fileURLToPath(import.meta.url));
  const envPath = path.resolve(dir, "../.env");
  if (!fs.existsSync(envPath)) return;
  const text = fs.readFileSync(envPath, "utf8");
  for (const line of text.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const i = t.indexOf("=");
    if (i <= 0) continue;
    const key = t.slice(0, i).trim();
    let val = t.slice(i + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    if (process.env[key] === undefined) process.env[key] = val;
  }
}
