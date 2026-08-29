/**
 * The glossary's job is to stop the console contradicting itself. A glossary
 * that drifts from the thing it documents does the opposite — it becomes one
 * more surface disagreeing with the others, and the most authoritative-looking
 * one at that.
 *
 * So this suite reads `docs/reference/status-vocabulary.md`, the canonical
 * five-dimension table, and fails when a value documented there has no entry
 * in the glossary. The compile side is already covered: the readiness and
 * maturity groups are `Record`s over their unions, so a new union member is a
 * type error. This closes the other direction.
 *
 * PARSER NON-VACUITY. A test that reads a file and asserts over what it found
 * passes trivially when it finds nothing — the failure mode that makes a gate
 * worse than no gate. The first assertions here are therefore about the PARSE
 * itself: five dimension rows, a floor on token count. Break the table format
 * or move the file and this suite goes red instead of quietly green.
 */
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { GLOSSARY_GROUPS, allGlossaryTerms, filterGlossary } from './glossary';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const VOCABULARY_DOC = join(REPO_ROOT, 'docs', 'reference', 'status-vocabulary.md');

interface DimensionRow {
  dimension: string;
  tokens: string[];
}

/**
 * Pull the five-dimension table out of the vocabulary doc.
 *
 * Only the Values column (index 1 of the cells) is read for tokens — the
 * Source column legitimately carries backticked things that are not status
 * values (`git status`, `pushed_at`), and sweeping those in would make the
 * test demand glossary entries for field names.
 */
function parseDimensionRows(markdown: string): DimensionRow[] {
  const rows: DimensionRow[] = [];
  for (const line of markdown.split(/\r?\n/)) {
    if (!line.startsWith('|')) continue;
    const cells = line.split('|').slice(1, -1).map(c => c.trim());
    if (cells.length < 2) continue;

    // Dimension names are bolded in the first column; the header and the
    // delimiter row are neither bolded nor value-bearing.
    const nameMatch = /^\*\*(.+?)\*\*$/.exec(cells[0]);
    if (!nameMatch) continue;

    const tokens = [...cells[1].matchAll(/`([^`]+)`/g)].map(m => m[1]);
    if (tokens.length === 0) continue;
    rows.push({ dimension: nameMatch[1], tokens });
  }
  return rows;
}

const markdown = readFileSync(VOCABULARY_DOC, 'utf8');
const dimensionRows = parseDimensionRows(markdown);

describe('status-vocabulary.md parses', () => {
  it('finds the five independent dimensions', () => {
    // If this drops to 0 the sync assertions below become vacuous, so the
    // count is asserted before anything is checked against it.
    expect(dimensionRows.map(r => r.dimension)).toEqual([
      'Working tree',
      'Remote drift',
      'Dispatch readiness',
      'Roadmap maturity',
      'Execution lane',
    ]);
  });

  it('finds a plausible number of status values', () => {
    const total = dimensionRows.reduce((n, r) => n + r.tokens.length, 0);
    expect(total).toBeGreaterThanOrEqual(15);
  });
});

describe('the glossary covers the canonical vocabulary', () => {
  const documented = new Set(allGlossaryTerms().map(t => t.token).filter((t): t is string => Boolean(t)));

  for (const row of dimensionRows) {
    it(`documents every ${row.dimension} value`, () => {
      const missing = row.tokens.filter(token => !documented.has(token));
      expect(missing).toEqual([]);
    });
  }
});

describe('the glossary is internally sound', () => {
  it('gives every term a definition and a stated basis', () => {
    const incomplete = allGlossaryTerms()
      .filter(t => !t.term.trim() || !t.definition.trim() || !t.basis.trim())
      .map(t => t.term);
    expect(incomplete).toEqual([]);
  });

  it('never shows the same display term twice', () => {
    const seen = new Map<string, number>();
    for (const t of allGlossaryTerms()) seen.set(t.term, (seen.get(t.term) ?? 0) + 1);
    expect([...seen.entries()].filter(([, n]) => n > 1).map(([term]) => term)).toEqual([]);
  });

  it('disambiguates values that two dimensions share', () => {
    // The vocabulary doc's central promise is that no two dimensions share a
    // WORD in the UI. `ready` and `blocked` are the two machine values that
    // legitimately appear in more than one dimension, so their display terms
    // must be qualified — this is the assertion that stops a future edit
    // renaming "Blocked (execution lane)" back to plain "Blocked".
    const byToken = new Map<string, string[]>();
    for (const t of allGlossaryTerms()) {
      if (!t.token) continue;
      byToken.set(t.token, [...(byToken.get(t.token) ?? []), t.term]);
    }
    for (const [token, terms] of byToken) {
      if (terms.length < 2) continue;
      expect(new Set(terms).size, `"${token}" is shared but its display terms collide`).toBe(terms.length);
    }
  });

  it('leaves no group empty', () => {
    expect(GLOSSARY_GROUPS.filter(g => g.terms.length === 0).map(g => g.id)).toEqual([]);
  });
});

describe('filterGlossary', () => {
  it('returns everything for an empty query', () => {
    expect(filterGlossary('   ')).toBe(GLOSSARY_GROUPS);
  });

  it('matches on the term itself and drops groups with no hit', () => {
    const results = filterGlossary('L3');
    expect(results.length).toBeGreaterThan(0);
    for (const group of results) expect(group.terms.length).toBeGreaterThan(0);
    expect(results.flatMap(g => g.terms).some(t => t.token === 'L3-Contract-Ready')).toBe(true);
  });

  it('matches on the basis, so an operator can search for what computed a number', () => {
    const results = filterGlossary('pushed_at');
    expect(results.flatMap(g => g.terms).map(t => t.token)).toContain('behind');
  });

  it('returns no groups when nothing matches', () => {
    expect(filterGlossary('zzz-not-a-term')).toEqual([]);
  });
});
