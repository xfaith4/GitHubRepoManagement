#!/usr/bin/env node
// UI debt ratchet — audit follow-up.
//
// One counted class of debt, too large to fix now and easy to grow by accident:
//
//   outlineNone   `focus:outline-none` / `outline-none` without a sibling ring
//                 or outline utility — the pattern that made keyboard focus
//                 invisible before the global :focus-visible rule landed.
//
// RETIRED 2026-09-01: tinyText, which counted text at or below 12px. It was
// built when 86% of the console's text sat under 12px by accident, and its
// job was to stop that number growing while a per-view pass brought it down.
//
// The Nocturne migration (MIGRATION.md §4) makes the density deliberate: the
// console is an operator tool whose type ladder runs 10px eyebrows, 11px meta,
// 12-13px body, and "the density is the point — an operator sees the whole
// state without scrolling." A gate that fails the design it was asked to build
// is not measuring debt any more, it is measuring the design.
//
// It was also already half-blind. The regex only ever matched INTEGER px
// (`text-[0..12px]`), so the ladder's 11.5px and 12.5px steps — the two the
// design leans on hardest — passed it unseen. Re-baselining it upward would
// have left a gate that counts a third of what it claims to and reports the
// rest as clean, which is worse than no gate: it launders the debt as
// measured. Retired rather than widened, because the thing it forbids is now
// the thing the design requires.
//
// Text CONTRAST is the rule that would actually serve this design, and it is
// still absent for the reason given below — it needs a real composited DOM.
//
// This fails ONLY on the delta against a committed baseline. A check that fails
// on the existing debt is an alarm nobody arms: it gets commented out inside a
// week and then nothing is counting at all, which is how 21 button colors and
// 600-odd tiny-text nodes accumulated unnoticed in the first place.
//
// Usage:
//   node tools/Measure-UiRatchet.mjs            # check against the baseline
//   node tools/Measure-UiRatchet.mjs --update   # re-baseline (only ever DOWN)
//
// Deliberately NOT counted #1: TEXT CONTRAST. Static analysis cannot see it.
// Real failures here are alpha-modified utilities on translucent stacks that
// exist as no token at all. Measured example, confirmed to the digit:
//
//   gray-900  ->  + bg-gray-800/50  ->  + bg-red-900/20  ->  text-red-400/80
//   composited = 3.97:1        (naive, ignoring every alpha = 3.47:1)
//
// Neither number is reachable by pairing class names: the effective background
// is three layers deep and none of the layers is the element's own. A scan
// that assumes a flat opaque ancestor reports "all pass" while 50 live
// failures sit on one tab -- which is worse than no rule, because it launders
// the debt as measured-and-clean. Measuring this needs computed style off a
// real composited DOM (headless browser); this repo has no browser harness,
// so the rule is deliberately absent rather than present and wrong.
//
// Deliberately NOT counted #2: button background colors. There is no canonical
// set of 21 to compare against — they are ad hoc, so a checker cannot tell a
// legitimate new one from an accidental one. That rule is a consequence of the
// design-system pass, not a substitute for it; see the roadmap item.

import { readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SCAN_DIR = join(ROOT, 'frontend');
const BASELINE = join(ROOT, 'tools', 'ui-ratchet-baseline.json');
const RETIRED_KEYS = new Set(['tinyText']);

const OUTLINE_NONE = /\b(?:focus:)?outline-none\b/g;
const HAS_RING = /\b(?:focus:|focus-visible:)?(?:ring|outline)-(?!none)/;

function sourceFiles(dir, acc = []) {
  for (const entry of readdirSync(dir)) {
    if (entry === 'node_modules' || entry === 'dist' || entry === 'build') continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) sourceFiles(full, acc);
    else if (/\.(tsx|ts)$/.test(entry) && !/\.test\.tsx?$/.test(entry)) acc.push(full);
  }
  return acc;
}

function measure() {
  const counts = { outlineNone: 0 };
  const byFile = {};
  for (const file of sourceFiles(SCAN_DIR)) {
    const text = readFileSync(file, 'utf8');

    // An outline-none only counts as debt when nothing in the same className
    // restores a visible focus indicator.
    let outline = 0;
    for (const line of text.split(/\r?\n/)) {
      const hits = (line.match(OUTLINE_NONE) ?? []).length;
      if (hits > 0 && !HAS_RING.test(line)) outline += hits;
    }

    if (outline) {
      byFile[relative(ROOT, file).replace(/\\/g, '/')] = { outlineNone: outline };
    }
    counts.outlineNone += outline;
  }
  return { counts, byFile };
}

const { counts, byFile } = measure();

if (process.argv.includes('--update')) {
  writeFileSync(BASELINE, `${JSON.stringify({ counts, byFile }, null, 2)}\n`, 'utf8');
  console.log('Baseline written:', JSON.stringify(counts));
  process.exit(0);
}

let baseline;
try {
  baseline = JSON.parse(readFileSync(BASELINE, 'utf8'));
} catch {
  console.error(`No baseline at ${relative(ROOT, BASELINE)}. Run: node tools/Measure-UiRatchet.mjs --update`);
  process.exit(2);
}

if (baseline?.counts && typeof baseline.counts === 'object') {
  for (const key of RETIRED_KEYS) delete baseline.counts[key];
}

if (baseline?.byFile && typeof baseline.byFile === 'object') {
  for (const fileMetrics of Object.values(baseline.byFile)) {
    if (!fileMetrics || typeof fileMetrics !== 'object') continue;
    for (const key of RETIRED_KEYS) delete fileMetrics[key];
  }
}

let failed = false;
for (const [key, current] of Object.entries(counts)) {
  const allowed = baseline.counts[key] ?? 0;
  const delta = current - allowed;
  if (delta > 0) {
    failed = true;
    console.error(`FAIL  ${key}: ${current} (baseline ${allowed}, +${delta} new)`);
    // Name the files that grew, so the failure is actionable without a diff.
    for (const [file, cur] of Object.entries(byFile)) {
      const was = baseline.byFile?.[file]?.[key] ?? 0;
      if (cur[key] > was) console.error(`        ${file}: ${was} -> ${cur[key]}`);
    }
  } else {
    const moved = delta < 0 ? ` (${delta} — re-baseline with --update)` : '';
    console.log(`ok    ${key}: ${current} / ${allowed}${moved}`);
  }
}

if (failed) {
  console.error('\nNew UI debt was added. Use an existing token, or fix the line you touched.');
  process.exit(1);
}
