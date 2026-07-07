#!/usr/bin/env node
/**
 * NAV-AI-2 dry-run CLI — read-only Navigation Complexity Analyzer.
 *
 * Usage:
 *   node workers/learning/analyze_nav_complexity_cli.js [path-to-json-or-jsonl]
 *
 * If no path is given, uses fixtures/nav_complexity_events_sample.json.
 *
 * This script is advisory-only. It does not connect to live ingest, workers,
 * or Flutter runtime. Output is stdout JSON.
 */

const fs = require("node:fs");
const path = require("node:path");
const { analyzeNavComplexityEvents } = require("./nav_complexity_analyzer.js");

function main() {
  const argPath = process.argv[2];
  const inputPath =
    argPath ??
    path.join(__dirname, "fixtures", "nav_complexity_events_sample.json");

  if (!fs.existsSync(inputPath)) {
    console.error(`NAV-AI-2: input not found: ${inputPath}`);
    process.exit(1);
  }

  const raw = fs.readFileSync(inputPath, "utf8");
  let payload = raw;
  const trimmed = raw.trim();
  if (trimmed.startsWith("[")) {
    payload = JSON.parse(trimmed);
  }

  const report = analyzeNavComplexityEvents(payload);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

main();
