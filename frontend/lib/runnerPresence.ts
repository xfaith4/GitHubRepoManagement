// Operator-runner presence (Release 3.0).
//
// The portal enqueues work it structurally cannot execute: `gh agent-task`
// needs an OAuth credential and `claude` needs an authenticated session, and the
// LocalSystem service holds neither. Execution happens in
// Invoke-RoadmapTaskRunner.ps1, running as the operator.
//
// That leaves a failure with no symptom: queueing into an empty room looks
// exactly like queueing into a running one. The request succeeds, the entry is
// written, and the operator finds out when nothing ever leaves `queued`. This
// module turns `GET /api/roadmap/runner` into the warning the dispatch surfaces
// show BEFORE the work is queued.

export type RunnerState = 'present' | 'stale' | 'absent';

export interface RunnerPresencePayload {
  state?: string;
  present?: boolean;
  hostname?: string;
  user?: string;
  pid?: number;
  mode?: string;
  pollSeconds?: number;
  claimedCount?: number;
  lastHeartbeatAt?: string | null;
  secondsSinceBeat?: number | null;
  staleAfterSeconds?: number;
  message?: string;
  queuedTotal?: number;
  queuedClaude?: number;
  queuedCopilot?: number;
  /** Queued tasks with no runner to pick them up. Zero when one is present. */
  strandedCount?: number;
  /** Oldest still-queued entry's timestamp (ISO) — the queue-age alarm's raw fact. */
  oldestQueuedAt?: string | null;
  /**
   * The command that starts a runner, with the script's ABSOLUTE path, built by
   * the host from its workspace root. The relative form only works from a shell
   * already inside the repo — an elevated terminal opens in the user profile.
   */
  startCommand?: string;
}

export type RunnerSeverity = 'ok' | 'warning' | 'error' | 'unknown';

export interface RunnerPresenceView {
  severity: RunnerSeverity;
  label: string;
  detail: string;
  /** True when the operator should act before queueing more work. */
  needsAttention: boolean;
  /** True when a dispatch surface should warn that nothing will pick this up. */
  warnBeforeQueueing: boolean;
  /**
   * Release 3.5 milestone 6 — hours the oldest queued task has sat unclaimed,
   * when that exceeds a day. Non-null escalates the header indicator to an
   * alarm regardless of presence: a present runner that claims nothing is the
   * same operator problem as an absent one.
   */
  queueAgeAlarmHours: number | null;
}

/**
 * Fallback for when the host has not said where the repo is (status call
 * failed). Relative, so it only works from a shell already inside the repo —
 * which is why every surface prefers the host's absolute form through
 * runnerStartCommand(payload).
 */
const RUNNER_COMMAND_FALLBACK = 'pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1';

const QUEUE_AGE_ALARM_MS = 24 * 60 * 60 * 1000;

function computeQueueAgeAlarmHours(payload: RunnerPresencePayload | null | undefined, nowMs: number): number | null {
  const raw = payload?.oldestQueuedAt;
  if (!raw) return null;
  const queuedMs = Date.parse(raw);
  if (Number.isNaN(queuedMs)) return null;
  const ageMs = nowMs - queuedMs;
  if (ageMs <= QUEUE_AGE_ALARM_MS) return null;
  return Math.floor(ageMs / (60 * 60 * 1000));
}

/**
 * Classify runner presence into one renderable state.
 *
 * A missing payload is 'unknown' and still warns before queueing. Reporting
 * "a runner is ready" because the status call failed is the false-green this
 * surface exists to prevent — and unlike an automation badge, acting on it
 * costs the operator a wizard's worth of refinement work.
 */
export function resolveRunnerPresence(
  payload: RunnerPresencePayload | null | undefined,
  nowMs: number = Date.now()
): RunnerPresenceView {
  if (!payload) {
    return {
      severity: 'unknown',
      label: 'Runner unknown',
      detail: `Could not read runner status. If no runner is running, queued work will wait: ${runnerStartCommand(null)}`,
      needsAttention: false,
      warnBeforeQueueing: true,
      queueAgeAlarmHours: null,
    };
  }

  const queueAgeAlarmHours = computeQueueAgeAlarmHours(payload, nowMs);

  const stranded = Number(payload.strandedCount ?? 0);
  const strandedSuffix =
    stranded > 0 ? ` ${stranded} task${stranded === 1 ? '' : 's'} already queued and waiting.` : '';

  if (payload.state === 'present' || payload.present === true) {
    const host = [payload.hostname, payload.user].filter(Boolean).join('\\');
    return {
      // A present runner with day-old queued work has stopped claiming -- the
      // same operator problem as an absent one, escalated the same way.
      severity: queueAgeAlarmHours != null ? 'warning' : 'ok',
      label: queueAgeAlarmHours != null ? 'Queue stalled' : 'Runner ready',
      detail: queueAgeAlarmHours != null
        ? `Runner alive but the oldest queued task has waited ${queueAgeAlarmHours}h unclaimed.`
        : host ? `Operator runner alive on ${host}.` : 'Operator runner alive.',
      needsAttention: queueAgeAlarmHours != null,
      warnBeforeQueueing: queueAgeAlarmHours != null,
      queueAgeAlarmHours,
    };
  }

  if (payload.state === 'stale') {
    return {
      severity: 'warning',
      label: 'Runner stalled',
      detail:
        (payload.message ?? 'The runner has stopped reporting in.') + strandedSuffix,
      needsAttention: true,
      warnBeforeQueueing: true,
      queueAgeAlarmHours,
    };
  }

  return {
    severity: 'error',
    label: 'No runner',
    detail:
      `Nothing will execute queued work until a runner runs: ${runnerStartCommand(payload)}` + strandedSuffix,
    needsAttention: stranded > 0 || queueAgeAlarmHours != null,
    warnBeforeQueueing: true,
    queueAgeAlarmHours,
  };
}

/**
 * The command an operator runs to fix an absent runner.
 *
 * Prefers the host's absolute form. The header's Copy button handed the
 * relative form to an elevated terminal that opened in the user profile, and
 * pwsh answered "not recognized as the name of a script file" — the host knew
 * the workspace root the whole time. The operator should never have to supply
 * it; the relative form survives only for a status call that failed.
 */
export function runnerStartCommand(payload?: RunnerPresencePayload | null): string {
  const fromHost = typeof payload?.startCommand === 'string' ? payload.startCommand.trim() : '';
  return fromHost.length > 0 ? fromHost : RUNNER_COMMAND_FALLBACK;
}

export interface DispatchGate {
  /** False when a control that queues work must render disabled. */
  canQueue: boolean;
  /**
   * The unmet precondition, in the operator's terms. Rendered next to the
   * disabled control — a greyed button with no reason is worse than a failing
   * one, because the operator cannot tell broken from not-yet-applicable.
   */
  unmetPrecondition: string;
  /** Label for the deliberate override, empty when no override is offered. */
  overrideLabel: string;
}

/**
 * May this surface queue work right now?
 *
 * Release 3.1 — the dispatch wizard's last step used to be enabled whatever the
 * runner was doing, so the operator spent the refinement work and then queued
 * into an empty room. Six entries sat at `queued` from 2026-08-01 to 2026-08-11
 * that way.
 *
 * 'unknown' does NOT block. A failed status call is not evidence that nothing
 * is listening, and blocking on it would dead-end the operator over a hiccup on
 * a different route — the same dead end from the other direction. The banner
 * still warns; only a positive absent/stale reading disables the control.
 */
export function resolveDispatchGate(
  payload: RunnerPresencePayload | null | undefined
): DispatchGate {
  const view = resolveRunnerPresence(payload);
  if (view.severity === 'ok' || view.severity === 'unknown') {
    return { canQueue: true, unmetPrecondition: '', overrideLabel: '' };
  }

  const stranded = Number(payload?.strandedCount ?? 0);
  const pile =
    stranded > 0
      ? ` ${stranded} task${stranded === 1 ? '' : 's'} already queued with nothing to claim ${stranded === 1 ? 'it' : 'them'}.`
      : '';

  return {
    canQueue: false,
    unmetPrecondition:
      `${view.label}: nothing would pick this up. Start the operator runner first — ${runnerStartCommand(payload)}.${pile}`,
    overrideLabel: 'Queue anyway',
  };
}
