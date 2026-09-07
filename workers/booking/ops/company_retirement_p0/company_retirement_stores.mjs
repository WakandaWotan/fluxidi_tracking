import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  EXPLICIT_RETIREMENT_CANDIDATES,
  isAllowedPhaseAWriteKey,
  isSecretBearingKey,
} from "./company_retirement_policy.mjs";
import { isHardProtectedCompanyCode } from "../../modules/company_registry_tombstone_guard.mjs";

export function parseWranglerJson(stdout) {
  let text = String(stdout || "");
  const npmIdx = text.search(/npm notice/i);
  if (npmIdx >= 0) text = text.slice(0, npmIdx);
  text = text
    .split(/\r?\n/)
    .filter((line) => line && !/wrangler|update available|──/i.test(line))
    .join("\n")
    .trim();
  if (!text) return null;
  if (/not found|does not exist|Couldn't find|The specified key does not exist/i.test(text)
    && !/"company_code"|"total"|"companies"/.test(text)) {
    return null;
  }
  const jsonStart = text.indexOf("{");
  const jsonEnd = text.lastIndexOf("}");
  if (jsonStart >= 0 && jsonEnd > jsonStart) {
    try {
      return JSON.parse(text.slice(jsonStart, jsonEnd + 1));
    } catch {
      // fall through
    }
  }
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

export function createWranglerKv({
  namespaceId,
  cwd,
  allowWrites = false,
  allowedCodes = EXPLICIT_RETIREMENT_CANDIDATES,
} = {}) {
  if (!namespaceId) throw new Error("namespace_id_required");
  return {
    async get(key) {
      const result = spawnSync(
        "npx",
        ["wrangler", "kv", "key", "get", `--namespace-id=${namespaceId}`, "--remote", "--config=.\\wrangler.toml", key],
        { encoding: "utf8", cwd, shell: true },
      );
      const combined = `${result.stdout || ""}\n${result.stderr || ""}`;
      if (/not found|does not exist|Couldn't find|The specified key does not exist/i.test(combined)
        && !/"company_code"|"total"|"companies"/.test(result.stdout || "")) {
        return null;
      }
      return parseWranglerJson(result.stdout);
    },
    async put(key, value) {
      if (!allowWrites) throw new Error("production_write_forbidden");
      if (isSecretBearingKey(key)) {
        throw new Error("refusing_to_log_or_rewrite_secret_via_cli");
      }
      if (!isAllowedPhaseAWriteKey(key, allowedCodes)) {
        throw new Error(`forbidden_phase_a_key:${key}`);
      }
      const companyFromKey = String(key).match(/FLX-[0-9]{4,12}/)?.[0];
      if (companyFromKey && isHardProtectedCompanyCode(companyFromKey)) {
        throw new Error(`protected_company_write_forbidden:${companyFromKey}`);
      }
      const dir = mkdtempSync(join(tmpdir(), "retire-kv-put-"));
      const file = join(dir, "value.json");
      try {
        writeFileSync(file, String(value ?? ""), "utf8");
        const result = spawnSync(
          "npx",
          ["wrangler", "kv", "key", "put", `--namespace-id=${namespaceId}`, "--remote", "--config=.\\wrangler.toml", key, `--path=${file}`],
          { encoding: "utf8", cwd, shell: true },
        );
        if (result.status !== 0) {
          throw new Error("production_kv_put_failed");
        }
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
      return true;
    },
    async delete() {
      throw new Error("production_delete_forbidden_in_phase_a");
    },
    async list() {
      throw new Error("kv_list_forbidden");
    },
  };
}

export function createMemoryKv(seed = {}) {
  const map = new Map(Object.entries(seed));
  return {
    map,
    async get(key) {
      return map.has(key) ? map.get(key) : null;
    },
    async put(key, value) {
      map.set(key, value);
    },
    async delete(key) {
      map.delete(key);
    },
    async head(key) {
      return map.has(key) ? { key } : null;
    },
    async list() {
      throw new Error("kv_list_forbidden");
    },
  };
}

export const BOOKING_KV_ID = "6805da1ffefe4a3982b4c419250c59b1";
export const TRACKING_KV_ID = "e457c0f51cfe44bca031250a0485b31e";
export const INVOICE_KV_ID = "c945929b64a743fdb10e09059d835746";
