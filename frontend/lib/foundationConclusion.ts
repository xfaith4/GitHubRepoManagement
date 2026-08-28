// Release 3.6 milestone 2 (backend setup) — the outcome card's data layer.
//
// Pure normalizers over the conclusion payloads served by
// GET /api/portfolio/conclusions, GET /api/portfolio/conclusions/{repoId},
// the `outcome` summary on /api/operations/repos entries, and the
// `conclusion` block on /api/operations/repos/{repoId} and /api/repo/evaluate.
// No fetch, no React: the card renders from these shapes, the tests pin them.

export type FoundationConclusionKind = 'strengthen' | 'appropriate-as-is' | 'insufficiently-understood';
export type FoundationDomainStatus = 'present' | 'weak' | 'missing' | 'not-applicable' | 'not-scored';

export const FOUNDATION_CONCLUSIONS: readonly FoundationConclusionKind[] = ['strengthen', 'appropriate-as-is', 'insufficiently-understood'];
export const FOUNDATION_DOMAIN_STATUSES: readonly FoundationDomainStatus[] = ['present', 'weak', 'missing', 'not-applicable', 'not-scored'];

export interface FoundationNextAction {
  domain: string;
  kind: string;
  label: string;
  method: 'GET' | 'POST';
  route: string;
  body: Record<string, string>;
  previewFirst: boolean;
}

export interface FoundationDomainRecord {
  domain: string;
  title: string;
  status: FoundationDomainStatus;
  evidence: string[];
  nextAction: FoundationNextAction | null;
}

export interface RepositoryConclusion {
  schemaVersion: string;
  repoId: string;
  repoName: string;
  kind: string;
  kindBasis: string;
  conclusion: FoundationConclusionKind;
  reason: string;
  basis: string[];
  domains: FoundationDomainRecord[];
  nextAction: FoundationNextAction | null;
  maturityLevel: string;
  lifecycleState: string;
  generatedAt: string;
}

/** The list-row view: enough to render a badge, a one-line why, and one action. */
export interface RepositoryOutcomeSummary {
  conclusion: FoundationConclusionKind;
  reason: string;
  kind: string;
  gapCount: number;
  gapDomains: string[];
  nextActionKind: string | null;
  nextActionLabel: string | null;
  nextActionRoute: string | null;
  holds: boolean;
}

export interface ConclusionContract {
  holds: boolean;
  violations: string[];
}

/**
 * Whether the index these conclusions were drawn from still describes the
 * portfolio. Absent means NOT ESTABLISHED, never fresh: on 2026-08-27 a
 * six-hour-old index reported 0 of 9 dispatch-ready repositories and every
 * surface rendered it as fact.
 */
export interface ConclusionBasis {
  indexStale: boolean;
  indexAgeHours: number | null;
  indexGeneratedAt: string | null;
  reasons: string[];
}

export const UNESTABLISHED_BASIS: ConclusionBasis = {
  indexStale: true,
  indexAgeHours: null,
  indexGeneratedAt: null,
  reasons: ['The freshness of the index behind these conclusions was not established, so they cannot be presented as current.'],
};

export function normalizeConclusionBasis(raw: unknown): ConclusionBasis {
  if (!raw || typeof raw !== 'object') return UNESTABLISHED_BASIS;
  const d = raw as Record<string, unknown>;
  // Only an explicit false counts as fresh. Anything missing or malformed
  // stays stale — the whole point is that silence is not reassurance.
  const stale = d.indexStale === false ? false : true;
  const age = typeof d.indexAgeHours === 'number' && Number.isFinite(d.indexAgeHours) ? d.indexAgeHours : null;
  const reasons = Array.isArray(d.reasons)
    ? d.reasons.map(r => String(r)).filter(r => r.trim().length > 0)
    : [];
  return {
    indexStale: stale,
    indexAgeHours: age,
    indexGeneratedAt: typeof d.indexGeneratedAt === 'string' && d.indexGeneratedAt ? d.indexGeneratedAt : null,
    reasons: stale && reasons.length === 0 ? UNESTABLISHED_BASIS.reasons : reasons,
  };
}

export interface PortfolioConclusionsResult {
  schemaVersion: string;
  generatedAt: string;
  count: number;
  totalCount: number;
  filter: FoundationConclusionKind | null;
  byConclusion: Record<FoundationConclusionKind, number>;
  byKind: Record<string, number>;
  coverage: Record<string, Record<FoundationDomainStatus, number>>;
  contract: ConclusionContract;
  basis: ConclusionBasis;
  items: RepositoryConclusion[];
  cacheSource: string;
}

/** What the card shows when the backend produced no reason. Never a maturity code. */
export const MISSING_REASON_TEXT = 'No reason was recorded for this conclusion.';

const asString = (value: unknown, fallback = ''): string => (value === null || value === undefined ? fallback : String(value));
const asStringArray = (value: unknown): string[] => (Array.isArray(value) ? value.map(item => String(item)).filter(item => item.trim().length > 0) : []);

export function isFoundationConclusionKind(value: unknown): value is FoundationConclusionKind {
  return typeof value === 'string' && (FOUNDATION_CONCLUSIONS as readonly string[]).includes(value);
}

export function isFoundationDomainStatus(value: unknown): value is FoundationDomainStatus {
  return typeof value === 'string' && (FOUNDATION_DOMAIN_STATUSES as readonly string[]).includes(value);
}

/** A bare maturity code is not a reason; the card must never print one as the whole explanation. */
function normalizeReason(value: unknown): string {
  const text = asString(value).trim();
  if (!text || /^L[0-4]-[A-Za-z-]+[.!]?$/.test(text)) return MISSING_REASON_TEXT;
  return text;
}

export function normalizeFoundationNextAction(raw: unknown): FoundationNextAction | null {
  if (!raw || typeof raw !== 'object') return null;
  const action = raw as Record<string, unknown>;
  const route = asString(action.route).trim();
  if (!route) return null;
  const bodyRaw = action.body && typeof action.body === 'object' ? (action.body as Record<string, unknown>) : {};
  const body: Record<string, string> = {};
  for (const [key, value] of Object.entries(bodyRaw)) body[key] = asString(value);
  return {
    domain: asString(action.domain),
    kind: asString(action.kind),
    label: asString(action.label, route),
    method: asString(action.method, 'POST').toUpperCase() === 'GET' ? 'GET' : 'POST',
    route,
    body,
    previewFirst: action.previewFirst === undefined ? true : Boolean(action.previewFirst),
  };
}

export function normalizeFoundationDomainRecord(raw: unknown): FoundationDomainRecord | null {
  if (!raw || typeof raw !== 'object') return null;
  const record = raw as Record<string, unknown>;
  const domain = asString(record.domain).trim();
  if (!domain) return null;
  return {
    domain,
    title: asString(record.title, domain),
    status: isFoundationDomainStatus(record.status) ? record.status : 'not-scored',
    evidence: asStringArray(record.evidence),
    nextAction: normalizeFoundationNextAction(record.nextAction),
  };
}

export function normalizeRepositoryConclusion(raw: unknown): RepositoryConclusion | null {
  if (!raw || typeof raw !== 'object') return null;
  const c = raw as Record<string, unknown>;
  if (!isFoundationConclusionKind(c.conclusion)) return null;
  const domains = Array.isArray(c.domains)
    ? c.domains.map(normalizeFoundationDomainRecord).filter((d): d is FoundationDomainRecord => d !== null)
    : [];
  return {
    schemaVersion: asString(c.schemaVersion, 'v1'),
    repoId: asString(c.repoId),
    repoName: asString(c.repoName),
    kind: asString(c.kind, 'unknown'),
    kindBasis: asString(c.kindBasis),
    conclusion: c.conclusion,
    reason: normalizeReason(c.reason),
    basis: asStringArray(c.basis),
    domains,
    nextAction: normalizeFoundationNextAction(c.nextAction),
    maturityLevel: asString(c.maturityLevel, 'L0-Absent'),
    lifecycleState: asString(c.lifecycleState),
    generatedAt: asString(c.generatedAt),
  };
}

export function normalizeRepositoryOutcomeSummary(raw: unknown): RepositoryOutcomeSummary | null {
  if (!raw || typeof raw !== 'object') return null;
  const s = raw as Record<string, unknown>;
  if (!isFoundationConclusionKind(s.conclusion)) return null;
  const route = asString(s.nextActionRoute).trim();
  return {
    conclusion: s.conclusion,
    reason: normalizeReason(s.reason),
    kind: asString(s.kind, 'unknown'),
    gapCount: Number(s.gapCount ?? 0) || 0,
    gapDomains: asStringArray(s.gapDomains),
    nextActionKind: route ? asString(s.nextActionKind) || null : null,
    nextActionLabel: route ? asString(s.nextActionLabel) || null : null,
    nextActionRoute: route || null,
    holds: s.holds === undefined ? true : Boolean(s.holds),
  };
}

/** Derive the summary from a full conclusion (the detail and evaluate payloads carry the full object). */
export function summarizeRepositoryConclusion(conclusion: RepositoryConclusion, contract?: ConclusionContract | null): RepositoryOutcomeSummary {
  const gaps = conclusion.domains.filter(d => d.status === 'missing' || d.status === 'weak');
  return {
    conclusion: conclusion.conclusion,
    reason: conclusion.reason,
    kind: conclusion.kind,
    gapCount: gaps.length,
    gapDomains: gaps.map(d => d.domain),
    nextActionKind: conclusion.nextAction?.kind ?? null,
    nextActionLabel: conclusion.nextAction?.label ?? null,
    nextActionRoute: conclusion.nextAction?.route ?? null,
    holds: contract ? contract.holds : true,
  };
}

export function normalizeConclusionContract(raw: unknown): ConclusionContract {
  if (!raw || typeof raw !== 'object') return { holds: false, violations: ['no contract block in the payload'] };
  const c = raw as Record<string, unknown>;
  return { holds: Boolean(c.holds), violations: asStringArray(c.violations) };
}

function normalizeCounts<K extends string>(raw: unknown, keys: readonly K[]): Record<K, number> {
  const out = {} as Record<K, number>;
  for (const key of keys) out[key] = 0;
  if (raw && typeof raw === 'object') {
    for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
      (out as Record<string, number>)[key] = Number(value ?? 0) || 0;
    }
  }
  return out;
}

export function normalizePortfolioConclusionsResult(raw: unknown): PortfolioConclusionsResult {
  const d = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const items = Array.isArray(d.items)
    ? d.items.map(normalizeRepositoryConclusion).filter((c): c is RepositoryConclusion => c !== null)
    : [];
  const coverage: Record<string, Record<FoundationDomainStatus, number>> = {};
  if (d.coverage && typeof d.coverage === 'object') {
    for (const [domain, row] of Object.entries(d.coverage as Record<string, unknown>)) {
      coverage[domain] = normalizeCounts(row, FOUNDATION_DOMAIN_STATUSES);
    }
  }
  return {
    schemaVersion: asString(d.schemaVersion, 'v1'),
    generatedAt: asString(d.generatedAt),
    count: Number(d.count ?? items.length) || items.length,
    totalCount: Number(d.totalCount ?? d.count ?? items.length) || items.length,
    filter: isFoundationConclusionKind(d.filter) ? d.filter : null,
    byConclusion: normalizeCounts(d.byConclusion, FOUNDATION_CONCLUSIONS),
    byKind: normalizeCounts(d.byKind, [] as string[]),
    coverage,
    contract: normalizeConclusionContract(d.contract),
    basis: normalizeConclusionBasis(d.basis),
    items,
    cacheSource: asString(d.cacheSource),
  };
}

// ── Presentation helpers the card and the list share ──────────────────────────

export interface ConclusionPresentation {
  label: string;
  tone: 'attention' | 'healthy' | 'unknown';
  /** True for every conclusion: appropriate-as-is is a first-class, filterable outcome. */
  filterable: true;
}

export function describeConclusion(kind: FoundationConclusionKind): ConclusionPresentation {
  switch (kind) {
    case 'strengthen':
      return { label: 'Strengthen', tone: 'attention', filterable: true };
    case 'appropriate-as-is':
      return { label: 'Appropriate as-is', tone: 'healthy', filterable: true };
    case 'insufficiently-understood':
    default:
      return { label: 'Insufficiently understood', tone: 'unknown', filterable: true };
  }
}

export function describeDomainStatus(status: FoundationDomainStatus): { label: string; counts: boolean } {
  switch (status) {
    case 'present': return { label: 'Present', counts: true };
    case 'weak': return { label: 'Weak', counts: true };
    case 'missing': return { label: 'Missing', counts: true };
    case 'not-applicable': return { label: 'Not applicable', counts: false };
    case 'not-scored':
    default: return { label: 'Observed, not scored', counts: false };
  }
}

// ── Next-action safety ────────────────────────────────────────────────────────
// The action is DATA: it arrives from foundation-domains.json by way of the
// API. Data must not be able to make the browser POST wherever it likes, so the
// card runs an action only when its route is one of the preview-first flows
// this product already exposes. An unrecognised route still renders — with its
// label and the reason it is not runnable — because silently hiding it would
// leave a conclusion with no visible next step.
export const RUNNABLE_NEXT_ACTION_ROUTES: readonly string[] = [
  '/api/roadmap/repair/preview',
  '/api/readme/standardize/preview',
  '/api/repository-improvement/preview',
  '/api/roadmap/dispatch/check',
];

export function isRunnableNextAction(action: FoundationNextAction | null | undefined): boolean {
  if (!action) return false;
  if (!RUNNABLE_NEXT_ACTION_ROUTES.includes(action.route)) return false;
  // Every runnable flow identifies its repository; an action with no body would
  // ask the backend to guess which repo the operator meant.
  return Object.values(action.body).some(value => value.trim().length > 0);
}

/** Why an action cannot be run, for the card to show instead of a dead button. */
export function explainUnrunnableAction(action: FoundationNextAction | null | undefined): string | null {
  if (!action) return null;
  if (!RUNNABLE_NEXT_ACTION_ROUTES.includes(action.route)) {
    return `${action.route} is not one of this console's preview-first flows, so it cannot be run from here.`;
  }
  if (!Object.values(action.body).some(value => value.trim().length > 0)) {
    return 'This action names no repository, so it cannot be run from here.';
  }
  return null;
}

/** Filter a list of entries carrying an outcome summary by conclusion; `null` keeps everything. */
export function filterByConclusion<T extends { outcome?: RepositoryOutcomeSummary | null }>(entries: T[], conclusion: FoundationConclusionKind | null): T[] {
  if (!conclusion) return entries;
  return entries.filter(entry => entry.outcome?.conclusion === conclusion);
}
