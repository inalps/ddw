#!/usr/bin/env node
// _ddw_read_config.mjs — read a dotted key path from ddw.json
// Usage: node _ddw_read_config.mjs <key.path> [<consumer_root>]
// Exit 0: found and non-null (prints value to stdout)
// Exit 1: not found, null, or ddw.json missing (prints reason to stderr)

import { readFileSync } from 'fs';
import { resolve, join } from 'path';

const [, , keyPath, consumerRoot] = process.argv;

if (!keyPath) {
  process.stderr.write('Usage: _ddw_read_config.mjs <key.path> [<consumer_root>]\n');
  process.exit(1);
}

const root = consumerRoot ? resolve(consumerRoot) : process.cwd();
const configPath = join(root, 'ddw.json');

let config;
try {
  const raw = readFileSync(configPath, 'utf8');
  config = JSON.parse(raw);
} catch (err) {
  if (err.code === 'ENOENT') {
    process.stderr.write(`ddw.json not found at ${configPath}\n`);
  } else {
    process.stderr.write(`Failed to parse ddw.json: ${err.message}\n`);
  }
  process.exit(1);
}

const parts = keyPath.split('.');
let value = config;
for (const part of parts) {
  if (value == null || typeof value !== 'object') {
    process.stderr.write(`Key not found: ${keyPath}\n`);
    process.exit(1);
  }
  value = value[part];
}

if (value === undefined || value === null) {
  process.stderr.write(`Key is null or undefined: ${keyPath}\n`);
  process.exit(1);
}

if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
  process.stdout.write(String(value) + '\n');
} else {
  process.stdout.write(JSON.stringify(value) + '\n');
}

process.exit(0);
