// Readiness for unattended work (operator correction, 2026-09-01).
//
// This replaces the `value` figure the landing table printed beside effort.
// That number came from `value-scoring.json`, which scores a pending ROADMAP
// ITEM on impact, unblock potential and risk reduction — business value.
// Printing it against a repository turned the landing screen into a ranking of
// repositories by worth, and the operator's position is explicit: every
// repository has its own purpose and all of them are actively useful, so
// nothing here may rank by usefulness.
//
// What the console MAY measure is whether an agent can work in a repository
// without asking a human anything. That is the only thing README, ROADMAP,
// spec docs and the L0–L4 ladder are for, and it is the only justification any
// of them gets. So the figure beside a row is now four named checks:
//
//   docs present              an agent has a statement of purpose and a plan
//   roadmap machine-readable  items can actually be selected and dispatched
//   clean working tree        dispatch is not blocked by uncommitted work
//   CI present                a run can be judged without a human looking
//
// Deliberately NOT a weighted 0–100 composite. A composite needs weights, the
// weights need a rationale, and the rationale needs a legend on the screen —
// three new concepts to explain one number. "3 of 4" needs none of them, and
// it names WHICH check is missing, which is the only actionable part.
//
// An absent input is `unmeasured`, never a failure. A missing CI signal does
// not mean CI is absent; it means nobody looked. Counting it as a failure
// would invent a number, which is the thing this file exists to prevent.

import type { OperationsRepoEntry } from '../types';

export type ReadinessState = 'ready' | 'not-ready' | 'unmeasured';

export type ReadinessFactorKey = 'docs' | 'roadmap-machine-readable' | 'clean-tree' | 'ci';

export interface ReadinessFactor {
  key: ReadinessFactorKey;
  /** Says what it measures, in the words the check uses. */
  label: string;
  state: ReadinessState;
  /** One sentence. Why this check reads the way it does. */
  detail: string;
}

export interface UnattendedReadiness {
  factors: ReadinessFactor[];
  /** Checks that passed. */
  ready: number;
  /** Checks that returned an answer at all. */
  measured: number;
  /** Always 4 — the checks are fixed, so a missing one is visible. */
  total: number;
  /** e.g. "3 of 4 ready" or "2 of 3 ready · CI unmeasured". */
  summary: string;
}

/** The roadmap states an agent can actually select work from. */
const MACHINE_READABLE_ROADMAP = new Set(['pending', 'complete']);

function docsFactor(entry: Partial<OperationsRepoEntry>): ReadinessFactor {
  const hasReadme = entry.hasReadme;
  const hasRoadmap = entry.hasRoadmap;
  if (typeof hasReadme !== 'boolean' || typeof hasRoadmap !== 'boolean') {
    return {
      key: 'docs',
      label: 'Docs present',
      state: 'unmeasured',
      detail: 'Nobody has checked whether a README and a ROADMAP exist here.',
    };
  }
  if (hasReadme && hasRoadmap) {
    return {
      key: 'docs',
      label: 'Docs present',
      state: 'ready',
      detail: 'A README states the purpose and a ROADMAP states the plan.',
    };
  }
  const missing = [!hasReadme ? 'README.md' : null, !hasRoadmap ? 'ROADMAP.md' : null]
    .filter(Boolean)
    .join(' and ');
  return {
    key: 'docs',
    label: 'Docs present',
    state: 'not-ready',
    detail: `${missing} is missing, so an agent has to ask what this repository is for.`,
  };
}

function roadmapFactor(entry: Partial<OperationsRepoEntry>): ReadinessFactor {
  const state = entry.roadmapState;
  if (!state) {
    return {
      key: 'roadmap-machine-readable',
      label: 'Roadmap machine-readable',
      state: 'unmeasured',
      detail: 'The roadmap has not been parsed, so nobody knows whether work can be selected from it.',
    };
  }
  if (MACHINE_READABLE_ROADMAP.has(state)) {
    return {
      key: 'roadmap-machine-readable',
      label: 'Roadmap machine-readable',
      state: 'ready',
      detail: 'Items can be selected and dispatched without a human reading the file.',
    };
  }
  // 'no-checklist' is a SOUND document with no `- [ ]` items. It must never be
  // described as damaged — that wording sent operators to repair working files.
  const detail =
    state === 'no-checklist'
      ? 'The roadmap is sound but records no "- [ ]" items, so there is nothing in it to dispatch.'
      : state === 'missing'
        ? 'There is no ROADMAP.md, so there is no plan to select work from.'
        : 'ROADMAP.md could not be parsed, so no item in it can be ranked or dispatched.';
  return { key: 'roadmap-machine-readable', label: 'Roadmap machine-readable', state: 'not-ready', detail };
}

function treeFactor(entry: Partial<OperationsRepoEntry>): ReadinessFactor {
  const dirty = entry.localDirtyCount;
  if (typeof dirty !== 'number' || !Number.isFinite(dirty)) {
    return {
      key: 'clean-tree',
      label: 'Clean working tree',
      state: 'unmeasured',
      detail: 'The working tree has not been read, so it cannot be called clean.',
    };
  }
  if (dirty === 0) {
    return {
      key: 'clean-tree',
      label: 'Clean working tree',
      state: 'ready',
      detail: 'Nothing uncommitted stands between an agent and a dispatch.',
    };
  }
  return {
    key: 'clean-tree',
    label: 'Clean working tree',
    state: 'not-ready',
    detail: `${dirty} uncommitted ${dirty === 1 ? 'file' : 'files'} block dispatch.`,
  };
}

function ciFactor(entry: Partial<OperationsRepoEntry>): ReadinessFactor {
  const hasCi = entry.hasCiSignal;
  if (typeof hasCi !== 'boolean') {
    return {
      key: 'ci',
      label: 'CI present',
      state: 'unmeasured',
      detail: 'Nobody has looked for a CI signal, so its absence is not established.',
    };
  }
  return hasCi
    ? {
        key: 'ci',
        label: 'CI present',
        state: 'ready',
        detail: 'A run can be judged green or red without a human looking at it.',
      }
    : {
        key: 'ci',
        label: 'CI present',
        state: 'not-ready',
        detail: 'No CI signal, so an unattended run has nothing to prove itself against.',
      };
}

/**
 * Four checks, in the order an agent hits them: understand the repo, select
 * the work, get a clean tree, prove the result.
 */
export function assessUnattendedReadiness(entry: Partial<OperationsRepoEntry>): UnattendedReadiness {
  const factors = [docsFactor(entry), roadmapFactor(entry), treeFactor(entry), ciFactor(entry)];
  const ready = factors.filter(f => f.state === 'ready').length;
  const measured = factors.filter(f => f.state !== 'unmeasured').length;
  const unmeasured = factors.filter(f => f.state === 'unmeasured');

  // The denominator is what was MEASURED, never the full four — saying
  // "2 of 4" when one check never ran reports an absence as a failure.
  let summary = `${ready} of ${measured} ready`;
  if (unmeasured.length > 0) {
    summary += ` · ${unmeasured.map(f => f.label.toLowerCase()).join(', ')} unmeasured`;
  }
  if (measured === 0) summary = 'unmeasured — no check has run for this repository';

  return { factors, ready, measured, total: factors.length, summary };
}

/**
 * The freshness stamp that rides beside a readiness figure.
 *
 * NOT a staleness banner. The banner was removed by operator decision
 * (2026-08-30) because a landing page that opens with a warning reads as a
 * broken product. This is the opposite thing: a quiet fact, always present,
 * never coloured — because a readiness figure is the one number an operator
 * would act on and be wrong about if it were old.
 */
export function describeAssessedAt(basis?: { indexGeneratedAt: string | null; indexAgeHours: number | null } | null): string {
  if (!basis || !basis.indexGeneratedAt) return 'assessed — time not recorded';
  const hours = basis.indexAgeHours;
  if (typeof hours !== 'number' || !Number.isFinite(hours)) return `assessed ${basis.indexGeneratedAt}`;
  if (hours < 1) return 'assessed under an hour ago';
  if (hours < 2) return 'assessed 1 hour ago';
  if (hours < 48) return `assessed ${Math.round(hours)} hours ago`;
  return `assessed ${Math.round(hours / 24)} days ago`;
}
