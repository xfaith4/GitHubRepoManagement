// Readiness for unattended work (operator correction, 2026-09-01).
//
// The figure beside a Today row is four named checks — docs present, roadmap
// machine-readable, clean working tree, CI present — never a weighted 0–100
// composite, and an absent input is `unmeasured`, never a failure.
//
// Release 4.0 phase A moved the assessment itself to the server
// (`Get-UnattendedReadiness` in backend/modules/portfolio/Portfolio.Ranking.ps1),
// because readiness is one of the ranking's keys and the ranking now has one
// home. It arrives on every operations entry as `ranking.readiness`. This file
// keeps the shape the UI renders and the freshness stamp that rides beside it.

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

/**
 * The freshness stamp that rides beside a readiness figure.
 *
 * NOT a staleness banner. The banner was removed by operator decision
 * (2026-08-30) because a landing page that opens with a warning reads as a
 * broken product. This is the opposite thing: a quiet fact, never coloured —
 * because a readiness figure is the one number an operator would act on and be
 * wrong about if it were old. Null when the time was never recorded: a column
 * of "time not recorded" carries no value, so the view leaves it out.
 */
export function describeAssessedAt(basis?: { indexGeneratedAt: string | null; indexAgeHours: number | null } | null): string | null {
  if (!basis || !basis.indexGeneratedAt) return null;
  const hours = basis.indexAgeHours;
  if (typeof hours !== 'number' || !Number.isFinite(hours)) return `assessed ${basis.indexGeneratedAt}`;
  if (hours < 1) return 'assessed under an hour ago';
  if (hours < 2) return 'assessed 1 hour ago';
  if (hours < 48) return `assessed ${Math.round(hours)} hours ago`;
  return `assessed ${Math.round(hours / 24)} days ago`;
}
