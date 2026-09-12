#!/usr/bin/env node
// ARB key-parity checker. Run by CI (.github/workflows/mobile.yml) and `make l10n`.
// Fails when any locale is missing a key that the template has, or has an extra one.
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ARB_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'lib', 'app', 'l10n');
const TEMPLATE = 'app_en.arb';

/** Translatable keys only: skip @-prefixed metadata and the @@locale header. */
const keysOf = (json) =>
  new Set(Object.keys(json).filter((k) => !k.startsWith('@')));

const files = readdirSync(ARB_DIR).filter((f) => f.endsWith('.arb')).sort();
if (!files.includes(TEMPLATE)) {
  console.error(`FAIL: template ${TEMPLATE} not found in ${ARB_DIR}`);
  process.exit(1);
}

const parsed = new Map();
for (const f of files) {
  try {
    parsed.set(f, JSON.parse(readFileSync(join(ARB_DIR, f), 'utf8')));
  } catch (e) {
    console.error(`FAIL: ${f} is not valid JSON — ${e.message}`);
    process.exit(1);
  }
}

const template = keysOf(parsed.get(TEMPLATE));
let failed = false;

for (const f of files) {
  const json = parsed.get(f);
  const keys = keysOf(json);
  const missing = [...template].filter((k) => !keys.has(k));
  const extra = [...keys].filter((k) => !template.has(k));

  if (f !== TEMPLATE && json['@@locale'] === undefined) {
    console.error(`FAIL ${f}: missing "@@locale" header`);
    failed = true;
  }
  const empty = [...keys].filter((k) => typeof json[k] === 'string' && json[k].trim() === '');
  if (empty.length) {
    console.error(`FAIL ${f}: empty translations -> ${empty.join(', ')}`);
    failed = true;
  }
  if (missing.length || extra.length) {
    console.error(`FAIL ${f}:`);
    if (missing.length) console.error(`  missing (${missing.length}): ${missing.join(', ')}`);
    if (extra.length) console.error(`  extra   (${extra.length}): ${extra.join(', ')}`);
    failed = true;
  } else {
    console.log(`OK   ${f} — ${keys.size} keys`);
  }
}

if (failed) {
  console.error('\nl10n parity check FAILED');
  process.exit(1);
}
console.log(`\nl10n parity check passed: ${files.length} locales x ${template.size} keys`);
