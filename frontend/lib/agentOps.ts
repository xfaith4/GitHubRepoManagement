// Agent Ops view model (2026-09-27).
//
// One page to see what the agents finished, what they are working on now, and
// what is next — with every operator decision as a card that carries its own
// button, and one control that stops all of it. This module is the pure half:
// it turns the host's payloads (agent runs, runner presence, packaged items,
// the ranked queue, the roadmap index) into rows, counts and actions. It reads
// no clock and calls no API, so every derivation here is unit-tested without a
// host.
//
// The delivery state is read from the run's own `deliveryState` field, which
// the host joins from the runner's task summary through Get-DeliveryState.
// The legacy `status` is mapped only when a host predates that field; the map
// is the one the design prototype shipped and is deliberately small.

import type { AgentRun, ExecutionLaneEntry, RoadmapEntry } from '../types';
import type { PackagedItem } from './packagedItems';
import type { RunnerPresencePayload } from './runnerPresence';

// ── Delivery states ────────────────────────────────────────────────────────

/** The 20-state happy path, DISCOVERED → COMPLETE, in order. */
export const DELIVERY_STATES = [
  'DISCOVERED',
  'FORMING',
  'QUALIFIED',
  'QUEUED',
  'CAPACITY_EVALUATING',
  'PROVIDER_SELECTED',
  'WORKSPACE_PREPARING',
  'AGENT_RUNNING',
  'LOCAL_VERIFYING',
  'IMPLEMENTATION_COMPLETE',
  'PUSHING',
  'PR_OPEN',
  'CI_PENDING',
  'CI_PASSED',
  'READY_FOR_OPERATOR',
  'OPERATOR_APPROVED',
  'MERGING',
  'MERGED',
  'POST_MERGE_VERIFYING',
  'COMPLETE',
] as const;

export type DeliveryState = (typeof DELIVERY_STATES)[number];

/**
 * Where an off-path state sits on the strip. A capacity wait is a pause at
 * scheduling; a CI failure is a CI_PENDING that answered badly; remediation
 * re-enters agent work; post-merge remediation re-enters verification.
 */
export const OFF_PATH_ANCHOR: Record<string, DeliveryState> = {
  CAPACITY_WAIT: 'CAPACITY_EVALUATING',
  CI_FAILED: 'CI_PENDING',
  REMEDIATION: 'AGENT_RUNNING',
  POST_MERGE_REMEDIATION: 'POST_MERGE_VERIFYING',
};

export const STOPPED_STATE = 'STOPPED';
export const CANCELLED_STATE = 'CANCELLED';

export type StageKey = 'intake' | 'sched' | 'agent' | 'ci' | 'op' | 'landed';

export interface DeliveryStage {
  key: StageKey;
  label: string;
  states: readonly string[];
}

/** The six operator-facing stages the twenty states roll up into. */
export const DELIVERY_STAGES: readonly DeliveryStage[] = [
  { key: 'intake', label: 'Queued', states: ['DISCOVERED', 'FORMING', 'QUALIFIED', 'QUEUED'] },
  { key: 'sched', label: 'Scheduling', states: ['CAPACITY_EVALUATING', 'PROVIDER_SELECTED', 'CAPACITY_WAIT'] },
  { key: 'agent', label: 'Agent working', states: ['WORKSPACE_PREPARING', 'AGENT_RUNNING', 'LOCAL_VERIFYING', 'IMPLEMENTATION_COMPLETE', 'REMEDIATION'] },
  { key: 'ci', label: 'PR & CI', states: ['PUSHING', 'PR_OPEN', 'CI_PENDING', 'CI_PASSED', 'CI_FAILED'] },
  { key: 'op', label: 'Operator gate', states: ['READY_FOR_OPERATOR', 'OPERATOR_APPROVED', 'MERGING'] },
  { key: 'landed', label: 'Landed', states: ['MERGED', 'POST_MERGE_VERIFYING', 'POST_MERGE_REMEDIATION', 'COMPLETE', 'CANCELLED'] },
];

/** Stages whose runs the "All work stop" would interrupt. */
const INTERRUPTIBLE_STAGES: readonly StageKey[] = ['sched', 'agent', 'ci'];
/** Stages that count as "in flight" on the board. */
const IN_FLIGHT_STAGES: readonly StageKey[] = ['sched', 'agent', 'ci', 'op'];

/**
 * Legacy ledger status → delivery state, for a host that does not send
 * `deliveryState`. The prototype's table, verbatim.
 */
const LEGACY_STATUS_TO_STATE: Record<string, string> = {
  active: 'AGENT_RUNNING',
  running: 'AGENT_RUNNING',
  'in-progress': 'AGENT_RUNNING',
  dispatched: 'QUEUED',
  queued: 'QUEUED',
  'awaiting-review': 'READY_FOR_OPERATOR',
  completed: 'COMPLETE',
  failed: 'CI_FAILED',
  blocked: 'CAPACITY_WAIT',
  monitoring: 'CI_PENDING',
};

const PROVIDER_LABELS: Record<string, string> = {
  claude: 'Claude Code',
  codex: 'Codex CLI',
  copilot: 'Copilot Agent',
  auto: 'Auto-route',
};

export function providerLabel(provider: string | null | undefined): string {
  const key = (provider ?? '').toLowerCase();
  return PROVIDER_LABELS[key] ?? (provider || 'unknown');
}

/** The state the strip should anchor on: a stopped run shows where it was. */
export function anchorState(state: string, stoppedFrom?: string | null): string {
  const base = state === STOPPED_STATE ? (stoppedFrom ?? 'AGENT_RUNNING') : state;
  return OFF_PATH_ANCHOR[base] ?? base;
}

export function stateIndex(state: string, stoppedFrom?: string | null): number {
  if (state === CANCELLED_STATE) return -1;
  return DELIVERY_STATES.indexOf(anchorState(state, stoppedFrom) as DeliveryState);
}

export function stageOfState(state: string, stoppedFrom?: string | null): DeliveryStage {
  const base = state === STOPPED_STATE ? (stoppedFrom ?? 'AGENT_RUNNING') : state;
  return DELIVERY_STAGES.find(stage => stage.states.includes(base)) ?? DELIVERY_STAGES[0];
}

/**
 * The delivery state for a run: the host's field first, the legacy status as
 * a fallback, QUEUED when neither says anything.
 */
export function deriveDeliveryState(run: Pick<AgentRun, 'deliveryState' | 'status'>): string {
  const fromHost = typeof run.deliveryState === 'string' ? run.deliveryState.trim().toUpperCase() : '';
  if (fromHost) return fromHost;
  return LEGACY_STATUS_TO_STATE[String(run.status ?? '').toLowerCase()] ?? 'QUEUED';
}

// ── Time ───────────────────────────────────────────────────────────────────

export function parseMs(value: string | null | undefined): number | null {
  if (!value) return null;
  const ms = Date.parse(value);
  return Number.isNaN(ms) ? null : ms;
}

/** "12s ago", "4m ago", "3h ago", "2d ago". Never negative. */
export function formatAgo(thenMs: number | null | undefined, nowMs: number): string {
  if (thenMs == null) return '—';
  const seconds = Math.max(0, Math.round((nowMs - thenMs) / 1000));
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

// ── Run rows ───────────────────────────────────────────────────────────────

export type RunTone = 'bad' | 'wait' | 'operator' | 'landed' | 'intake' | 'active' | 'cancelled';

export interface AgentOpsRun {
  run: AgentRun;
  id: string;
  repo: string;
  /** The stable id merge readiness and merge take; falls back to the name. */
  repoId: string;
  title: string;
  provider: string;
  providerLabel: string;
  state: string;
  stateLabel: string;
  stoppedFrom: string | null;
  remote: boolean;
  stage: DeliveryStage;
  /** Position on the 20-segment strip; -1 for a cancelled run. */
  index: number;
  tone: RunTone;
  attempt: number;
  updatedMs: number;
  prNumber: number | null;
  prUrl: string | null;
  /** The commit an approval would name. */
  sha: string | null;
  ciLabel: string;
  lastEvent: string;
  note: string | null;
}

function toneFor(state: string, stage: DeliveryStage): RunTone {
  if (state === STOPPED_STATE || state === 'CI_FAILED' || state === 'POST_MERGE_REMEDIATION') return 'bad';
  if (state === CANCELLED_STATE) return 'cancelled';
  if (state === 'READY_FOR_OPERATOR' || state === 'OPERATOR_APPROVED') return 'operator';
  if (state === 'CAPACITY_WAIT') return 'wait';
  if (stage.key === 'landed') return 'landed';
  if (stage.key === 'intake') return 'intake';
  return 'active';
}

/** One line for the CI column, from the run's Actions observation. */
export function describeCi(run: AgentRun): string {
  const actions = run.actions;
  if (!actions) return '';
  const status = String(actions.status ?? '').toLowerCase();
  const conclusion = String(actions.conclusion ?? '').toLowerCase();
  const name = actions.workflowName ? ` (${actions.workflowName})` : '';
  if (status === 'completed') {
    if (conclusion === 'success') return `Checks passing${name}`;
    if (conclusion === 'failure' || conclusion === 'timed_out' || conclusion === 'cancelled') return `Checks ${conclusion.replace('_', ' ')}${name}`;
    return conclusion ? `Checks ${conclusion}${name}` : `Checks completed${name}`;
  }
  if (status) return `Checks ${status.replace('_', ' ')}${name}`;
  return '';
}

function shortSha(sha: string | null | undefined): string | null {
  if (!sha) return null;
  return sha.length > 7 ? sha.slice(0, 7) : sha;
}

function lastEventFor(run: AgentRun, state: string): string {
  if (run.deliveryNote) return run.deliveryNote;
  if (state === 'READY_FOR_OPERATOR' && run.verifiedHeadSha) return `CI passed on ${shortSha(run.verifiedHeadSha)}`;
  if (run.operatorApproval?.sha) return `Operator approved ${shortSha(run.operatorApproval.sha)}`;
  if (run.headMovedAt) return 'Head moved after verification';
  if (run.prNumber) return `PR #${run.prNumber} ${run.prState ?? 'open'}`;
  return `Status: ${run.status}`;
}

export function toAgentOpsRun(run: AgentRun): AgentOpsRun {
  const state = deriveDeliveryState(run);
  const stoppedFrom = run.stoppedFrom ?? null;
  const stage = stageOfState(state, stoppedFrom);
  const provider = String(run.providerTool ?? 'auto').toLowerCase();
  const remote = run.stoppedRemote === true;
  const stateLabel = state === STOPPED_STATE
    ? `STOPPED · ${stoppedFrom ?? 'AGENT_RUNNING'}${remote ? ' · remote' : ''}`
    : state;
  return {
    run,
    id: run.runId,
    repo: run.repoName || 'unknown repo',
    repoId: run.repoId || run.repoName,
    title: run.selectedTaskText?.trim() || '(no task text)',
    provider,
    providerLabel: providerLabel(provider),
    state,
    stateLabel,
    stoppedFrom,
    remote,
    stage,
    index: stateIndex(state, stoppedFrom),
    tone: toneFor(state, stage),
    attempt: typeof run.attempt === 'number' && run.attempt > 0 ? run.attempt : Math.max(1, (run.metrics?.retries ?? 0) + 1),
    updatedMs: parseMs(run.updatedAt) ?? parseMs(run.createdAt) ?? 0,
    prNumber: run.prNumber ?? null,
    prUrl: run.prUrl ?? null,
    sha: run.verifiedHeadSha ?? run.prHeadSha ?? null,
    ciLabel: describeCi(run),
    lastEvent: lastEventFor(run, state),
    note: run.deliveryNote ?? null,
  };
}

/** In flight: scheduling through the operator gate, plus stopped runs; furthest along first. */
export function selectInFlight(rows: readonly AgentOpsRun[]): AgentOpsRun[] {
  return rows
    .filter(row => row.state === STOPPED_STATE || IN_FLIGHT_STAGES.includes(row.stage.key))
    .sort((a, b) => b.index - a.index || b.updatedMs - a.updatedMs);
}

/** Landed: the last N COMPLETE, MERGED, POST_MERGE_VERIFYING or CANCELLED runs, newest first. */
export function selectRecentlyCompleted(rows: readonly AgentOpsRun[], limit = 6): AgentOpsRun[] {
  const landed = new Set(['COMPLETE', 'MERGED', 'POST_MERGE_VERIFYING', CANCELLED_STATE]);
  return rows
    .filter(row => landed.has(row.state))
    .sort((a, b) => b.updatedMs - a.updatedMs)
    .slice(0, limit);
}

/** The runs an "All work stop" interrupts: scheduling, agent work and CI, excluding waits and already-stopped runs, plus a merge in progress. */
export function selectInterruptible(rows: readonly AgentOpsRun[]): AgentOpsRun[] {
  return rows.filter(row =>
    row.state === 'MERGING'
    || (INTERRUPTIBLE_STAGES.includes(row.stage.key) && row.state !== STOPPED_STATE && row.state !== 'CAPACITY_WAIT'),
  );
}

// ── Next up ────────────────────────────────────────────────────────────────

export interface NextUpRow {
  rank: number;
  repo: string;
  title: string;
  provider: string;
  providerLabel: string;
  score: number;
  state: string;
}

/** The ranked queue, highest value first; only entries still waiting. */
export function selectNextUp(entries: readonly ExecutionLaneEntry[] | null | undefined): NextUpRow[] {
  const waiting = (entries ?? []).filter(entry => entry.executionState === 'ready' || entry.executionState === 'idle');
  return waiting
    .slice()
    .sort((a, b) => (b.priorityScore ?? 0) - (a.priorityScore ?? 0))
    .map((entry, i) => ({
      rank: i + 1,
      repo: entry.repoName,
      title: entry.currentTaskText?.trim() || 'Next roadmap item',
      provider: 'auto',
      providerLabel: providerLabel('auto'),
      score: Number(entry.priorityScore ?? 0),
      state: entry.executionState === 'ready' ? 'QUALIFIED' : 'QUEUED',
    }));
}

// ── Operator actions ───────────────────────────────────────────────────────

export type OperatorActionOp =
  | { type: 'resume' }
  | { type: 'approve'; runId: string; sha: string }
  | { type: 'merge'; repoId: string; runId: string }
  | { type: 'refresh'; runId: string }
  | { type: 'cancel'; repoName: string; runId: string }
  | { type: 'approve-package'; packetId: string }
  | { type: 'reject-package'; packetId: string }
  | { type: 'details'; runId: string };

export interface OperatorActionButton {
  label: string;
  /** True when the button starts or writes something (amber emphasis). */
  consequence: boolean;
  /** True for the red stop/cancel family. */
  destructive?: boolean;
  op: OperatorActionOp;
}

export type OperatorActionKind = 'runner-held' | 'approve-sha' | 'merge' | 'ci-failed' | 'package-approval';

export interface OperatorAction {
  id: string;
  kind: OperatorActionKind;
  kindLabel: string;
  tone: 'crit' | 'accent' | 'neutral';
  repo: string;
  title: string;
  detail: string;
  primary: OperatorActionButton;
  secondary?: OperatorActionButton;
}

export interface OperatorActionInput {
  rows: readonly AgentOpsRun[];
  packages: readonly PackagedItem[];
  runner: RunnerPresencePayload | null;
  nowMs: number;
}

/**
 * Every decision waiting on the operator, in the order the handoff fixes:
 * runner held → approve verified SHA → ready to merge → CI failed → package
 * approval. Operator-queue items have no route yet (Lane 0.19) and are not
 * invented here.
 */
export function deriveOperatorActions(input: OperatorActionInput): OperatorAction[] {
  const actions: OperatorAction[] = [];
  const { rows, packages, runner, nowMs } = input;

  if (runner?.stoppedByOperator === true) {
    const interrupted = Number(runner.stopInterruptedCount ?? 0);
    const since = formatAgo(parseMs(runner.stoppedAt), nowMs);
    actions.push({
      id: 'runner-held',
      kind: 'runner-held',
      kindLabel: 'Runners held',
      tone: 'crit',
      repo: 'all',
      title: 'All work is stopped',
      detail: `${interrupted} run${interrupted === 1 ? '' : 's'} interrupted ${since}${runner.stopReason ? ` · “${runner.stopReason}”` : ''}. Queued work waits until you resume.`,
      primary: { label: 'Resume runners', consequence: true, op: { type: 'resume' } },
    });
  }

  for (const row of rows.filter(r => r.state === 'READY_FOR_OPERATOR')) {
    const sha = shortSha(row.sha);
    actions.push({
      id: `approve:${row.id}`,
      kind: 'approve-sha',
      kindLabel: 'Approve verified SHA',
      tone: 'accent',
      repo: row.repo,
      title: row.title,
      detail: `${row.prNumber ? `PR #${row.prNumber} · ` : ''}${sha ? `CI passed on ${sha}` : 'No verified commit reported yet'}${row.ciLabel ? ` · ${row.ciLabel}` : ''}`,
      primary: row.sha
        ? { label: `Approve ${sha}`, consequence: true, op: { type: 'approve', runId: row.id, sha: row.sha } }
        : { label: 'Re-evaluate run', consequence: true, op: { type: 'refresh', runId: row.id } },
      secondary: { label: 'Details', consequence: false, op: { type: 'details', runId: row.id } },
    });
  }

  for (const row of rows.filter(r => r.state === 'OPERATOR_APPROVED')) {
    const sha = shortSha(row.run.operatorApproval?.sha ?? row.sha);
    actions.push({
      id: `merge:${row.id}`,
      kind: 'merge',
      kindLabel: 'Ready to merge',
      tone: 'accent',
      repo: row.repo,
      title: row.title,
      detail: `Approved ${sha ?? 'a verified commit'}. Merging is irreversible and runs post-merge verification.`,
      primary: { label: row.prNumber ? `Merge PR #${row.prNumber}` : 'Merge', consequence: true, op: { type: 'merge', repoId: row.repoId, runId: row.id } },
      secondary: { label: 'Details', consequence: false, op: { type: 'details', runId: row.id } },
    });
  }

  for (const row of rows.filter(r => r.state === 'CI_FAILED')) {
    actions.push({
      id: `ci:${row.id}`,
      kind: 'ci-failed',
      kindLabel: 'CI failed',
      tone: 'crit',
      repo: row.repo,
      title: row.title,
      detail: `${row.prNumber ? `PR #${row.prNumber} · ` : ''}attempt ${row.attempt}${row.ciLabel ? ` · ${row.ciLabel}` : ''}. Re-evaluating re-reads the PR and CI; remediation is queued by policy, never from here.`,
      primary: { label: 'Re-evaluate run', consequence: true, op: { type: 'refresh', runId: row.id } },
      secondary: { label: 'Cancel', consequence: true, destructive: true, op: { type: 'cancel', repoName: row.repo, runId: row.id } },
    });
  }

  for (const item of packages.filter(p => p.status === 'pending-approval')) {
    const repo = item.repoName ?? item.packet?.repoName ?? 'unknown repo';
    const value = item.packet?.valueScore;
    const level = item.packet?.maturityLevel;
    actions.push({
      id: `package:${item.packetId}`,
      kind: 'package-approval',
      kindLabel: 'Package approval',
      tone: 'neutral',
      repo,
      title: item.packet?.itemText?.trim() || '(no item text)',
      detail: `Value ${value ?? '—'}${level ? ` · ${level}` : ''} · packaged ${formatAgo(parseMs(item.packagedAt), nowMs)}. Nothing runs until you approve.`,
      primary: { label: 'Approve & queue', consequence: true, op: { type: 'approve-package', packetId: item.packetId } },
      secondary: { label: 'Reject', consequence: true, op: { type: 'reject-package', packetId: item.packetId } },
    });
  }

  return actions;
}

/** The tab badge: how many decisions wait on the operator. Independent of the clock. */
export function countOperatorActions(runs: readonly AgentRun[], packages: readonly PackagedItem[], runner: RunnerPresencePayload | null): number {
  return deriveOperatorActions({ rows: runs.map(toAgentOpsRun), packages, runner, nowMs: 0 }).length;
}

// ── Activity feed ──────────────────────────────────────────────────────────

export interface ActivityEvent {
  atMs: number;
  repo: string;
  message: string;
  /** A failure, interrupt, stop or limit — rendered with the red dot. */
  bad: boolean;
  runId?: string;
}

const BAD_EVENT = /fail|interrupt|stop|limit/i;

function pushEvent(list: ActivityEvent[], atMs: number | null, repo: string, message: string, runId?: string): void {
  if (atMs == null) return;
  list.push({ atMs, repo, message, bad: BAD_EVENT.test(message), runId });
}

/**
 * The newest events the list payload can vouch for. Each run contributes the
 * timestamps its record carries — dispatch, agent start and finish, CI
 * observation, verification, approval, head movement — plus its last status
 * change; the runner hold contributes the stop itself.
 */
export function buildActivityFeed(rows: readonly AgentOpsRun[], runner: RunnerPresencePayload | null, limit = 14): ActivityEvent[] {
  const events: ActivityEvent[] = [];
  for (const row of rows) {
    const run = row.run;
    pushEvent(events, parseMs(run.metrics?.dispatchedAt ?? run.createdAt), row.repo, `Dispatched to ${row.providerLabel}`, row.id);
    pushEvent(events, parseMs(run.metrics?.agentStartedAt), row.repo, `Agent started (${row.providerLabel})`, row.id);
    pushEvent(events, parseMs(run.metrics?.agentCompletedAt), row.repo, 'Agent finished; implementation recorded', row.id);
    if (run.actions?.observedAt) {
      pushEvent(events, parseMs(run.actions.observedAt), row.repo, row.ciLabel || `CI ${run.actions.status}`, row.id);
    }
    pushEvent(events, parseMs(run.readyForOperatorAt), row.repo, `CI passed on ${shortSha(run.verifiedHeadSha) ?? 'the head'}; ready for operator`, row.id);
    pushEvent(events, parseMs(run.operatorApproval?.at), row.repo, `Operator approved ${shortSha(run.operatorApproval?.sha) ?? 'a commit'}`, row.id);
    pushEvent(events, parseMs(run.headMovedAt), row.repo, 'Head moved after verification; approval no longer applies', row.id);
    if (row.state === STOPPED_STATE) {
      pushEvent(events, row.updatedMs, row.repo, `Interrupted by All work stop${row.remote ? ' (remote; finishes on GitHub, not merged)' : ''}`, row.id);
    } else {
      pushEvent(events, row.updatedMs, row.repo, `${row.stateLabel}${row.note ? ` · ${row.note}` : ''}`, row.id);
    }
  }
  if (runner?.stoppedByOperator === true) {
    const count = Number(runner.stopInterruptedCount ?? 0);
    pushEvent(events, parseMs(runner.stoppedAt), 'operator', `ALL WORK STOP: ${count} run${count === 1 ? '' : 's'} interrupted${runner.stopReason ? ` (${runner.stopReason})` : ''}`);
  }
  return events.sort((a, b) => b.atMs - a.atMs).slice(0, limit);
}

// ── Roll-ups ───────────────────────────────────────────────────────────────

export interface StageCount {
  key: StageKey;
  label: string;
  count: number;
}

const DAY_MS = 86_400_000;

/** Runs per stage; the landed stage counts only the last day's completions so it does not grow forever. */
export function countByStage(rows: readonly AgentOpsRun[], nowMs: number): StageCount[] {
  return DELIVERY_STAGES.map(stage => ({
    key: stage.key,
    label: stage.label,
    count: rows.filter(row =>
      row.stage.key === stage.key
      && (stage.key !== 'landed' || row.state !== 'COMPLETE' || nowMs - row.updatedMs < DAY_MS),
    ).length,
  }));
}

export interface RepoProgress {
  repo: string;
  phase: string;
  done: number;
  total: number;
  active: number;
}

/** Roadmap progress per repository, with the number of runs in flight there. */
export function buildRepoProgress(entries: readonly RoadmapEntry[] | null | undefined, rows: readonly AgentOpsRun[]): RepoProgress[] {
  const inFlight = selectInFlight(rows);
  return (entries ?? [])
    .map(entry => {
      const done = Number(entry.completedCount ?? 0);
      const pending = Number(entry.pendingCount ?? 0);
      return {
        repo: entry.repoName,
        phase: entry.activeRelease?.releaseTitle || entry.activeRelease?.releaseName || entry.activePhasePlan?.phaseName || 'Roadmap',
        done,
        total: done + pending,
        active: inFlight.filter(row => row.repo === entry.repoName).length,
      };
    })
    .filter(row => row.total > 0)
    .sort((a, b) => b.active - a.active || b.total - b.done - (a.total - a.done) || a.repo.localeCompare(b.repo));
}

export interface PhaseRollup {
  repo: string;
  title: string;
  done: number;
  total: number;
  pct: number;
  phaseName: string | null;
  nextItem: string | null;
}

/**
 * The phase the band leads with: the repository with the most runs in flight,
 * then the most recently updated run's repository, then the first roadmap
 * entry that names an active release. Null when the index is empty.
 */
export function selectCurrentPhase(entries: readonly RoadmapEntry[] | null | undefined, rows: readonly AgentOpsRun[]): PhaseRollup | null {
  const list = entries ?? [];
  if (list.length === 0) return null;
  const inFlight = selectInFlight(rows);
  const counts = new Map<string, number>();
  for (const row of inFlight) counts.set(row.repo, (counts.get(row.repo) ?? 0) + 1);
  let chosen: RoadmapEntry | undefined;
  if (counts.size > 0) {
    const [topRepo] = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
    chosen = list.find(entry => entry.repoName === topRepo);
  }
  if (!chosen) {
    const latest = rows.slice().sort((a, b) => b.updatedMs - a.updatedMs)[0];
    if (latest) chosen = list.find(entry => entry.repoName === latest.repo);
  }
  if (!chosen) chosen = list.find(entry => entry.activeRelease) ?? list[0];
  const done = Number(chosen.completedCount ?? 0);
  const total = done + Number(chosen.pendingCount ?? 0);
  return {
    repo: chosen.repoName,
    title: chosen.activeRelease?.releaseTitle || chosen.activeRelease?.releaseName || 'Roadmap',
    done,
    total,
    pct: total > 0 ? Math.round((done / total) * 100) : 0,
    phaseName: chosen.activePhasePlan?.phaseName ?? null,
    nextItem: chosen.nextPendingItem?.text ?? null,
  };
}

// ── Stop dialog copy ───────────────────────────────────────────────────────

export function describeStopSummary(victims: readonly AgentOpsRun[]): string {
  const repos = [...new Set(victims.map(v => v.repo))];
  const n = victims.length;
  return `${n} run${n === 1 ? ' is' : 's are'} mid-flight (${repos.length ? repos.join(', ') : 'none'}). ${n === 1 ? 'It' : 'They'} will be interrupted now.`;
}

export function describeHeldBanner(runner: RunnerPresencePayload, nowMs: number): string {
  const n = Number(runner.stopInterruptedCount ?? 0);
  return `All work stopped ${formatAgo(parseMs(runner.stoppedAt), nowMs)}: ${n} run${n === 1 ? '' : 's'} interrupted${runner.stopReason ? ` · “${runner.stopReason}”` : ''}. Runners are held, so no new work is claimed.`;
}
