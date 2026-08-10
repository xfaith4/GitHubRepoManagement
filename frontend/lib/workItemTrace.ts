// Work-item trace view model (Release 3.1).
//
// Every stage of the north-star loop already wrote its own ledger; nothing
// joined them, so answering "what happened to this item?" meant reading four
// append-only files and inferring the links. GET /api/trace/{id} does the join
// server-side (Join-WorkItemTrace) and this module turns the result into
// something an operator can read at a glance.
//
// The one distinction worth preserving all the way to the pixel is `pending`
// vs `missing`. Both mean "this stage has no artifact", but `pending` means the
// chain has not reached it and `missing` means it demonstrably has — a broken
// link. Rendering them the same way is how a stalled loop reads as a young one.

export type TraceStageKey =
  | 'rank'
  | 'prompt'
  | 'dispatch'
  | 'agentRun'
  | 'actions'
  | 'mergeReadiness'
  | 'writeBack';

export type TraceStageStatus = 'complete' | 'active' | 'failed' | 'blocked' | 'pending' | 'missing';

export interface TraceStage {
  stage: TraceStageKey | string;
  label: string;
  order: number;
  status: TraceStageStatus | string;
  at?: string | null;
  detail?: string;
  artifact?: string | null;
  evidence?: Record<string, unknown> | null;
}

export interface TraceIdentity {
  packetId?: string | null;
  packagingRunId?: string | null;
  dispatchRunId?: string | null;
  agentRunId?: string | null;
  repoName?: string | null;
  repoId?: string | null;
  itemText?: string | null;
  branch?: string | null;
  roadmapPath?: string | null;
  prUrl?: string | null;
}

export interface WorkItemTrace {
  schemaVersion?: string;
  traceId: string;
  requestedId?: string | null;
  status: 'complete' | 'active' | 'failed' | 'blocked' | string;
  currentStage?: string | null;
  completeStageCount: number;
  stageCount: number;
  hasGaps: boolean;
  gaps: string[];
  identity: TraceIdentity;
  stages: TraceStage[];
  joinedAt?: string;
}

export type TraceSeverity = 'ok' | 'active' | 'error' | 'gap' | 'idle';

export interface TraceStageView {
  severity: TraceSeverity;
  label: string;
  /** True when the stage names a broken link rather than unreached work. */
  isGap: boolean;
}

const STAGE_STATUS_VIEW: Record<string, TraceStageView> = {
  complete: { severity: 'ok', label: 'Done', isGap: false },
  active: { severity: 'active', label: 'In progress', isGap: false },
  failed: { severity: 'error', label: 'Failed', isGap: false },
  blocked: { severity: 'error', label: 'Blocked', isGap: false },
  pending: { severity: 'idle', label: 'Not started', isGap: false },
  // A gap is styled apart from both "done" and "not started" on purpose: it is
  // the only status that means the chain is broken rather than in motion.
  missing: { severity: 'gap', label: 'No record', isGap: true },
};

const UNKNOWN_STAGE_VIEW: TraceStageView = { severity: 'idle', label: 'Unknown', isGap: false };

export function describeTraceStageStatus(status: string): TraceStageView {
  return STAGE_STATUS_VIEW[status] ?? UNKNOWN_STAGE_VIEW;
}

const TRACE_STATUS_VIEW: Record<string, { severity: TraceSeverity; label: string }> = {
  complete: { severity: 'ok', label: 'Loop complete' },
  active: { severity: 'active', label: 'In flight' },
  failed: { severity: 'error', label: 'Failed' },
  blocked: { severity: 'error', label: 'Blocked' },
};

export function describeTraceStatus(status: string): { severity: TraceSeverity; label: string } {
  return TRACE_STATUS_VIEW[status] ?? { severity: 'idle', label: status || 'Unknown' };
}

/** Stages in their canonical chain order, whatever order the payload arrived in. */
export function sortTraceStages(stages: TraceStage[]): TraceStage[] {
  return [...(stages ?? [])].sort((a, b) => Number(a?.order ?? 0) - Number(b?.order ?? 0));
}

/**
 * One line an operator can act on: where the item stands, and whether any link
 * in the chain is broken. Gaps lead, because a gap is the finding — progress
 * counts alone would let "6 of 7 done" hide a stage nothing ever recorded.
 */
export function summarizeTrace(trace: WorkItemTrace | null): string {
  if (!trace) return 'No trace loaded.';
  const stages = sortTraceStages(trace.stages ?? []);
  const current = stages.find(s => String(s.stage) === String(trace.currentStage ?? ''));
  const progress = `${trace.completeStageCount}/${trace.stageCount} stages complete`;

  if (trace.hasGaps) {
    const names = (trace.gaps ?? []).map(g => stageLabel(stages, g)).join(', ');
    return `${progress} — ${trace.gaps.length} broken link${trace.gaps.length === 1 ? '' : 's'} in the chain: ${names}.`;
  }
  if (trace.status === 'complete') return `${progress} — the item travelled the whole loop.`;
  if (current) return `${progress} — waiting at ${current.label.toLowerCase()}.`;
  return progress;
}

function stageLabel(stages: TraceStage[], key: string): string {
  const found = stages.find(s => String(s.stage) === key);
  return found ? found.label : key;
}

/** Every id the chain minted for this item, for display and for re-lookup. */
export function traceIdentityPairs(trace: WorkItemTrace | null): Array<{ label: string; value: string }> {
  if (!trace?.identity) return [];
  const id = trace.identity;
  const pairs: Array<{ label: string; value: string | null | undefined }> = [
    { label: 'Packet', value: id.packetId },
    { label: 'Packaging run', value: id.packagingRunId },
    { label: 'Dispatch run', value: id.dispatchRunId },
    { label: 'Agent run', value: id.agentRunId },
    { label: 'Branch', value: id.branch },
  ];
  return pairs
    .filter((p): p is { label: string; value: string } => typeof p.value === 'string' && p.value.trim().length > 0)
    .map(p => ({ label: p.label, value: p.value }));
}

/**
 * Evidence rendered as ordered label/value rows. Nulls and empty collections
 * are dropped: an evidence row with nothing in it is noise that makes the rows
 * that do carry a fact harder to see.
 */
export function traceEvidenceRows(stage: TraceStage | null): Array<{ label: string; value: string }> {
  if (!stage?.evidence) return [];
  const rows: Array<{ label: string; value: string }> = [];
  for (const [key, raw] of Object.entries(stage.evidence)) {
    if (raw === null || raw === undefined || raw === '') continue;
    if (Array.isArray(raw)) {
      if (raw.length === 0) continue;
      rows.push({ label: humanizeKey(key), value: raw.map(v => String(v)).join(', ') });
      continue;
    }
    if (typeof raw === 'object') continue;
    if (typeof raw === 'boolean' && raw === false) continue;
    rows.push({ label: humanizeKey(key), value: String(raw) });
  }
  return rows;
}

// Acronyms the camel-case split would otherwise mangle into "Pr url".
const EVIDENCE_KEY_LABELS: Record<string, string> = {
  prUrl: 'PR URL',
  prNumber: 'PR number',
  prState: 'PR state',
  agentTaskUrl: 'Agent task URL',
  commitSha: 'Commit SHA',
};

function humanizeKey(key: string): string {
  const override = EVIDENCE_KEY_LABELS[key];
  if (override) return override;
  const spaced = key.replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase();
  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}
