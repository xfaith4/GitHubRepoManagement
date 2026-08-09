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
}

const RUNNER_COMMAND = 'pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1';

/**
 * Classify runner presence into one renderable state.
 *
 * A missing payload is 'unknown' and still warns before queueing. Reporting
 * "a runner is ready" because the status call failed is the false-green this
 * surface exists to prevent — and unlike an automation badge, acting on it
 * costs the operator a wizard's worth of refinement work.
 */
export function resolveRunnerPresence(
  payload: RunnerPresencePayload | null | undefined
): RunnerPresenceView {
  if (!payload) {
    return {
      severity: 'unknown',
      label: 'Runner unknown',
      detail: `Could not read runner status. If no runner is running, queued work will wait: ${RUNNER_COMMAND}`,
      needsAttention: false,
      warnBeforeQueueing: true,
    };
  }

  const stranded = Number(payload.strandedCount ?? 0);
  const strandedSuffix =
    stranded > 0 ? ` ${stranded} task${stranded === 1 ? '' : 's'} already queued and waiting.` : '';

  if (payload.state === 'present' || payload.present === true) {
    const host = [payload.hostname, payload.user].filter(Boolean).join('\\');
    return {
      severity: 'ok',
      label: 'Runner ready',
      detail: host ? `Operator runner alive on ${host}.` : 'Operator runner alive.',
      needsAttention: false,
      warnBeforeQueueing: false,
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
    };
  }

  return {
    severity: 'error',
    label: 'No runner',
    detail:
      `Nothing will execute queued work until a runner runs: ${RUNNER_COMMAND}` + strandedSuffix,
    needsAttention: stranded > 0,
    warnBeforeQueueing: true,
  };
}

/** The command an operator runs to fix an absent runner. */
export function runnerStartCommand(): string {
  return RUNNER_COMMAND;
}
