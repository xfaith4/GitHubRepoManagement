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

import type { ProviderToken } from '../types';

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
  /**
   * H38-19 — kept, and kept meaning exactly what they meant before: everything
   * that is not copilot counts as claude, unknown tokens included. Every
   * surface still reads them, so narrowing them to "only claude" would silently
   * change numbers on screens this packet does not touch.
   */
  queuedClaude?: number;
  queuedCopilot?: number;
  /**
   * H38-18's per-provider backlog, one key per registry token plus `auto`.
   * Optional because a host older than that packet does not send it — absent
   * and "all zero" are different answers, and only the second is a backlog.
   */
  queuedByProvider?: Partial<Record<ProviderToken, number>>;
  /**
   * What a dispatch with no explicit target would actually do. Both null when
   * the host could not load its provider config: "no policy loaded" is not the
   * same as "routing is off", and a surface should be able to tell them apart.
   */
  dispatch?: { defaultTarget: ProviderToken | null; autoEnabled: boolean | null };
  /** Queued tasks with no runner to pick them up. Zero when one is present. */
  strandedCount?: number;
  /** Oldest still-queued entry's timestamp (ISO) — the queue-age alarm's raw fact. */
  oldestQueuedAt?: string | null;
  /**
   * The command that starts a runner, with the script's ABSOLUTE path, built by
   * the host from its workspace root. The relative form only works from a shell
   * already inside the repo — an elevated terminal opens in the user profile.
   *
   * Lane 0.20 demoted this from the remedy to the fallback. It is shown when the
   * console's own Start attempt FAILED, beside the error that attempt produced —
   * never as the first thing an operator is asked to do.
   */
  startCommand?: string;
  /**
   * Lane 0.20 — the operator pressed the kill switch and it is still held.
   *
   * Absent and false mean the same thing; only true is a hold. This is the one
   * field that separates "something is wrong" from "you did this on purpose",
   * and without it every surface renders a deliberate stop as a fault.
   */
  stoppedByOperator?: boolean;
  /** When the hold was taken (ISO), for attribution rather than alarm. */
  stoppedAt?: string | null;
  stoppedBy?: string | null;
  stopReason?: string | null;
  /**
   * Whether the scheduled task a Start would trigger is actually registered.
   * False means the installer was never run here, and a Start button would fail
   * every time — so the surface says that instead of offering the button.
   */
  startable?: boolean;
  taskName?: string;
}

/**
 * What the operator can do about the runner right now.
 *
 * Lane 0.20. The console used to hand over a command; this is the same
 * information expressed as an action, so the surface renders a control rather
 * than instructions. `kind: 'none'` is honest unavailability, and
 * `unavailableReason` is why — a greyed control with no reason reads as broken.
 */
export interface RunnerControlOffer {
  kind: 'start' | 'stop' | 'none';
  label: string;
  unavailableReason: string;
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
  /**
   * H38-19 — the backlog written per provider, e.g. `claude 2 · copilot 1`.
   *
   * Null rather than an empty string when nothing is queued or the host is too
   * old to send the map, so a caller renders nothing instead of an empty row.
   * Zero-count providers are omitted: "codex 0" is noise on a surface whose
   * whole job is to say what is waiting.
   */
  queuedByProviderSummary: string | null;
  /** Lane 0.20 — the control this state should render, if any. */
  control: RunnerControlOffer;
  /**
   * True when the runner is down because the operator stopped it. Surfaces use
   * it to drop the alarm styling: a held runner is the kill switch working, and
   * colouring it like a fault trains the operator to ignore the colour.
   */
  stoppedByOperator: boolean;
}

const NO_CONTROL: RunnerControlOffer = { kind: 'none', label: '', unavailableReason: '' };

/**
 * Which control to offer, from presence plus the hold.
 *
 * Start is offered for any down runner, held or not, because there is only one
 * start path by design: resuming is releasing the hold, and a second entry point
 * would be a second place for the two to drift.
 */
function resolveControlOffer(
  payload: RunnerPresencePayload | null | undefined,
  isPresent: boolean
): RunnerControlOffer {
  if (!payload) return NO_CONTROL;
  if (isPresent) return { kind: 'stop', label: 'Stop runners', unavailableReason: '' };
  // `startable` absent means a host older than this packet: it cannot say
  // whether the task exists, and refusing to offer the control on that silence
  // would disable the button against every host that has not restarted yet.
  if (payload.startable === false) {
    return {
      kind: 'none',
      label: '',
      unavailableReason:
        'No runner task is registered on this machine, so there is nothing to start. Register it once, unelevated: pwsh -File scripts/service/Install-RoadmapTaskRunner.ps1',
    };
  }
  return {
    kind: 'start',
    label: payload.stoppedByOperator === true ? 'Resume runners' : 'Start runner',
    unavailableReason: '',
  };
}

/** Attribution for a hold, as one sentence. Empty when nothing is held. */
function describeHold(payload: RunnerPresencePayload | null | undefined): string {
  if (payload?.stoppedByOperator !== true) return '';
  const who = (payload.stoppedBy ?? '').trim();
  const at = (payload.stoppedAt ?? '').trim();
  const when = at ? new Date(at) : null;
  const stamp = when && !Number.isNaN(when.getTime()) ? when.toLocaleString() : '';
  const by = who ? ` by ${who}` : '';
  const on = stamp ? ` on ${stamp}` : '';
  const why = (payload.stopReason ?? '').trim();
  return `Runners were stopped${by}${on}. Nothing restarts until you resume.${why ? ` ${why}` : ''}`;
}

/**
 * Fallback for when the host has not said where the repo is (status call
 * failed). Relative, so it only works from a shell already inside the repo —
 * which is why every surface prefers the host's absolute form through
 * runnerStartCommand(payload).
 */
const RUNNER_COMMAND_FALLBACK = 'pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1';

const QUEUE_AGE_ALARM_MS = 24 * 60 * 60 * 1000;

/**
 * H38-19 — the per-provider backlog as one readable line.
 *
 * Payload order is preserved rather than sorted: the host writes the registry's
 * own order (claude, codex, copilot, then auto), and re-sorting here would make
 * the reading order depend on the counts, which moves entries around between
 * polls for no reason.
 */
function summarizeQueuedByProvider(payload: RunnerPresencePayload | null | undefined): string | null {
  const map = payload?.queuedByProvider;
  if (!map) return null;
  const parts = Object.entries(map)
    .filter(([, count]) => Number(count) > 0)
    .map(([name, count]) => `${name} ${Number(count)}`);
  return parts.length > 0 ? parts.join(' · ') : null;
}

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
      detail: 'Could not read runner status. If no runner is running, queued work will wait.',
      needsAttention: false,
      warnBeforeQueueing: true,
      queueAgeAlarmHours: null,
      queuedByProviderSummary: null,
      control: NO_CONTROL,
      stoppedByOperator: false,
    };
  }

  const queueAgeAlarmHours = computeQueueAgeAlarmHours(payload, nowMs);
  const queuedByProviderSummary = summarizeQueuedByProvider(payload);
  const stoppedByOperator = payload.stoppedByOperator === true;

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
      queuedByProviderSummary,
      control: resolveControlOffer(payload, true),
      stoppedByOperator,
    };
  }

  // Lane 0.20 — a held runner is checked BEFORE stale/absent, because the same
  // missing heartbeat means two opposite things. Reported as a fault it would
  // read as the kill switch having broken something, and the console would push
  // the operator to undo the thing they just deliberately did.
  if (stoppedByOperator) {
    return {
      severity: 'warning',
      label: 'Runners stopped',
      detail: describeHold(payload) + strandedSuffix,
      // Deliberate, so not an alarm — but still true that nothing is being
      // worked, which is why it keeps warning before queueing.
      needsAttention: false,
      warnBeforeQueueing: true,
      queueAgeAlarmHours,
      queuedByProviderSummary,
      control: resolveControlOffer(payload, false),
      stoppedByOperator,
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
      queuedByProviderSummary,
      control: resolveControlOffer(payload, false),
      stoppedByOperator,
    };
  }

  return {
    severity: 'error',
    label: 'No runner',
    detail: 'Nothing will execute queued work until a runner is running.' + strandedSuffix,
    needsAttention: stranded > 0 || queueAgeAlarmHours != null,
    warnBeforeQueueing: true,
    queueAgeAlarmHours,
    queuedByProviderSummary,
    control: resolveControlOffer(payload, false),
    stoppedByOperator,
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

  // Lane 0.20 — the gate itself is unchanged and stays: it was
  // operator-verified on 2026-09-13 and refusing to queue into an empty room is
  // still right. What changed is the remedy it names. It used to end in a
  // command to paste, which made the operator the mechanism for something the
  // console can simply do.
  const remedy =
    view.control.kind === 'start'
      ? `Use ${view.control.label} to bring one up.`
      : view.control.unavailableReason || 'No runner can be started from here.';

  return {
    canQueue: false,
    unmetPrecondition: `${view.label}: nothing would pick this up. ${remedy}${pile}`,
    overrideLabel: 'Queue anyway',
  };
}
