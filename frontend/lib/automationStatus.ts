// Automation-status presentation (Release 2.7 Phase D).
//
// Interval firing is delegated to an external cron hitting
// POST /api/automation/run — nothing inside the app fires it. That makes the
// failure mode silence: if the cron stops, the config still reads "enabled",
// the run history simply stops growing, and no surface in the product changes.
// `GET /api/automation/status` derives the alert; this module turns that
// payload into the single labelled state every consumer renders, so the
// dashboard badge and any future surface cannot disagree about what "healthy"
// means.

export type AutomationSeverity = 'ok' | 'warning' | 'error' | 'off' | 'unknown';

export interface AutomationHealthPayload {
  enabled?: boolean;
  intervalMinutes?: number;
  runCount?: number;
  lastRunAt?: string | null;
  lastOutcome?: string;
  lastErrorCount?: number;
  minutesSinceLastRun?: number | null;
  expectedNextRunAt?: string | null;
  overdue?: boolean;
  consecutiveFailures?: number;
  healthy?: boolean;
  alert?: { severity?: string; code?: string; message?: string } | null;
}

export interface AutomationStatusView {
  severity: AutomationSeverity;
  /** Short badge label. */
  label: string;
  /** One-sentence explanation for the tooltip / detail line. */
  detail: string;
  /** True when the operator should act — drives the amber/red treatment. */
  needsAttention: boolean;
  /** Machine-readable alert code, when the backend raised one. */
  code: string | null;
}

/** Renders a minute count as a compact human duration ("3h 20m", "2d"). */
export function formatMinutesAgo(minutes: number | null | undefined): string {
  if (minutes === null || minutes === undefined || !Number.isFinite(minutes)) {
    return 'unknown';
  }
  const total = Math.max(0, Math.round(minutes));
  if (total < 1) return 'just now';
  if (total < 60) return `${total}m ago`;

  const hours = Math.floor(total / 60);
  if (hours < 24) {
    const rem = total % 60;
    return rem > 0 ? `${hours}h ${rem}m ago` : `${hours}h ago`;
  }

  const days = Math.floor(hours / 24);
  const remHours = hours % 24;
  return remHours > 0 ? `${days}d ${remHours}h ago` : `${days}d ago`;
}

/**
 * Classify an automation-status payload into one renderable state.
 *
 * A missing payload is 'unknown', never 'ok' — reporting healthy because the
 * status call failed is exactly the false-green this surface exists to prevent.
 * Disabled automation is 'off' and never needs attention: a feature that is
 * switched off is not a failure.
 */
export function resolveAutomationStatus(
  payload: AutomationHealthPayload | null | undefined
): AutomationStatusView {
  if (!payload) {
    return {
      severity: 'unknown',
      label: 'Automation unknown',
      detail: 'Automation status is unavailable — the status endpoint did not respond.',
      needsAttention: false,
      code: null,
    };
  }

  if (!payload.enabled) {
    return {
      severity: 'off',
      label: 'Automation off',
      detail: 'Scheduled automation is disabled. Enable it in Settings to keep favorites assessed automatically.',
      needsAttention: false,
      code: null,
    };
  }

  const alert = payload.alert ?? null;
  if (alert && alert.message) {
    const severity: AutomationSeverity = alert.severity === 'error' ? 'error' : 'warning';
    return {
      severity,
      label: severity === 'error' ? 'Automation failing' : 'Automation degraded',
      detail: alert.message,
      needsAttention: true,
      code: alert.code ?? null,
    };
  }

  const interval = payload.intervalMinutes ?? 0;
  const ago = formatMinutesAgo(payload.minutesSinceLastRun);
  return {
    severity: 'ok',
    label: 'Automation healthy',
    detail:
      payload.runCount && payload.runCount > 0
        ? `Last run ${ago}; running every ${interval} minutes.`
        : `Enabled on a ${interval}-minute interval.`,
    needsAttention: false,
    code: null,
  };
}
