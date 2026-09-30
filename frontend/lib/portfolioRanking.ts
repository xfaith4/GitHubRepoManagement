// Release 4.0 phase A — the one ranking, as the server sends it.
//
// Today used to rank the portfolio here in the browser while the Dispatch Board
// sorted the execution ledger by `priorityScore`, and one repository read #1 on
// Today and #8 on the board. The ranking now lives in exactly one place,
// `backend/modules/portfolio/Portfolio.Ranking.ps1`: every operations entry
// arrives with a `ranking`, and every board row with the same `portfolioRank`.
//
// This module only reads that payload. It holds no precedence table, no sort
// key and no readiness assessment — `tests/Test-OneRanking.ps1` fails if one
// comes back.

import type { ReadinessFactor, ReadinessState, UnattendedReadiness } from './unattendedReadiness';

export interface RankingEffort {
  workUnits: number | null;
  label: string;
  /** Cheap work first is a tiebreak, not a ranking principle. */
  band: 'small' | 'medium' | 'large' | 'unknown';
}

export interface PortfolioRanking {
  /** 1-based, on the one portfolio scale Today and the board share. */
  rank: number;
  scale: 'portfolio';
  /** The ordered signals behind the rank, most significant first. */
  basis: string[];
  /** One sentence: why this repository is where it is. */
  whyNow: string;
  /** Set only when the row sits above a repository readier for unattended work. */
  pinReason: string | null;
  readiness: UnattendedReadiness;
  effort: RankingEffort;
}

const READINESS_STATES: ReadonlySet<string> = new Set(['ready', 'not-ready', 'unmeasured']);
const EFFORT_BANDS: ReadonlySet<string> = new Set(['small', 'medium', 'large', 'unknown']);

function asArray(value: unknown): unknown[] {
  if (Array.isArray(value)) return value;
  // PowerShell's JSON writer can collapse a one-element array to its element.
  return value === null || value === undefined ? [] : [value];
}

function normalizeFactor(raw: unknown): ReadinessFactor | null {
  if (!raw || typeof raw !== 'object') return null;
  const f = raw as Record<string, unknown>;
  const state = String(f.state ?? '');
  if (!READINESS_STATES.has(state)) return null;
  return {
    key: String(f.key ?? '') as ReadinessFactor['key'],
    label: String(f.label ?? ''),
    state: state as ReadinessState,
    detail: String(f.detail ?? ''),
  };
}

function normalizeReadiness(raw: unknown): UnattendedReadiness {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const factors = asArray(r.factors).map(normalizeFactor).filter((f): f is ReadinessFactor => f !== null);
  return {
    factors,
    ready: Number(r.ready ?? 0) || 0,
    measured: Number(r.measured ?? 0) || 0,
    total: Number(r.total ?? factors.length) || factors.length,
    summary: typeof r.summary === 'string' && r.summary ? r.summary : 'unmeasured — no check has run for this repository',
  };
}

function normalizeEffort(raw: unknown): RankingEffort {
  const e = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const units = typeof e.workUnits === 'number' && Number.isFinite(e.workUnits) ? e.workUnits : null;
  const band = String(e.band ?? 'unknown');
  return {
    workUnits: units,
    label: typeof e.label === 'string' && e.label ? e.label : 'Effort not estimated',
    band: (EFFORT_BANDS.has(band) ? band : 'unknown') as RankingEffort['band'],
  };
}

/** Null when the host sent no ranking (an older host, or no index yet). */
export function normalizePortfolioRanking(raw: unknown): PortfolioRanking | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  const rank = Number(r.rank);
  if (!Number.isInteger(rank) || rank < 1) return null;
  return {
    rank,
    scale: 'portfolio',
    basis: asArray(r.basis).map(item => String(item)),
    whyNow: String(r.whyNow ?? ''),
    pinReason: typeof r.pinReason === 'string' && r.pinReason ? r.pinReason : null,
    readiness: normalizeReadiness(r.readiness),
    effort: normalizeEffort(r.effort),
  };
}
