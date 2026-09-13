import React, { useCallback, useState } from 'react';
import useRunnerControl from '../hooks/useRunnerControl';

/**
 * Release 3.5 milestone 6 — runner health beside `Backend: Online`, above the
 * fold on every tab.
 *
 * The review's sharpest Tier-3 finding: the single most consequential message
 * in the app ("Runner stalled: nothing would pick this up…") rendered as red
 * text below the fold while the header cheerfully said `6 active`. The system
 * knew it was broken and told you only if you scrolled. This pill is the
 * above-the-fold delivery: severity-colored, alarming on day-old queued work
 * even when the runner is present.
 *
 * Lane 0.20 replaced the popover's pasted command with the action itself. The
 * command survives in one place only — beside the error, when the console tried
 * to start a runner and could not.
 */
function RunnerHealthIndicator() {
  const { view, loaded, action, actionNote, failureCommand, start, stop } = useRunnerControl();
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  // A lone in-flight flag, so the only reason this control is ever disabled is
  // one the label already states ("Starting…"). Anything compound here would be
  // a precondition the operator is never told about.
  const busy = action !== 'idle';

  // Only ever the fallback command, and only after a failed attempt.
  const copyCommand = useCallback(async () => {
    if (!failureCommand) return;
    try {
      await navigator.clipboard.writeText(failureCommand);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard can be unavailable (permissions, non-secure context); the
      // command stays visible as selectable text either way.
    }
  }, [failureCommand]);

  const palette: Record<string, { pill: string; dot: string }> = {
    ok: { pill: 'bg-emerald-900/50 text-emerald-300 border border-emerald-700', dot: 'bg-emerald-400' },
    warning: { pill: 'bg-amber-900/50 text-amber-200 border border-amber-600', dot: 'bg-amber-400 animate-pulse' },
    error: { pill: 'bg-red-900/50 text-red-200 border border-red-700', dot: 'bg-red-400 animate-pulse' },
    unknown: { pill: 'bg-gray-700 text-gray-400', dot: 'bg-gray-500' },
  };
  const colors = palette[view.severity] ?? palette.unknown;

  return (
    <span className="relative inline-flex">
      <button
        type="button"
        data-testid="runner-health-indicator"
        onClick={() => setOpen(o => !o)}
        aria-expanded={open}
        aria-label={`Runner health: ${view.label}. ${view.detail}`}
        title={loaded ? view.detail : 'Checking runner status…'}
        className={`inline-flex items-center gap-1.5 min-h-[44px] sm:min-h-0 px-2.5 py-1 rounded-full text-xs font-medium cursor-pointer ${colors.pill}`}
      >
        <span className={`inline-block w-2 h-2 rounded-full ${colors.dot}`} />
        {view.label}
        {view.queueAgeAlarmHours != null && (
          <span className="font-semibold" data-testid="runner-queue-age">· queued {view.queueAgeAlarmHours}h</span>
        )}
      </button>

      {open && (
        <div
          data-testid="runner-health-popover"
          className="absolute right-0 top-full mt-2 z-50 w-80 rounded-lg border border-gray-600 bg-gray-800 p-3 text-left shadow-xl"
        >
          <p className="text-xs text-gray-200 mb-2">{view.detail}</p>
          {/* H38-19 — what is waiting, per provider. Rendered only when the
              host sends the map and something is actually queued, so an
              up-to-date host with an empty queue shows no empty row. */}
          {view.queuedByProviderSummary && (
            <p className="text-sm text-gray-300 mb-2" data-testid="runner-queued-by-provider">
              Queued: {view.queuedByProviderSummary}
            </p>
          )}
          {/* Lane 0.20 — the action, where the command used to be. A console
              that answers "paste this into a shell" has made its operator the
              mechanism for something it can simply do. */}
          {view.control.kind !== 'none' && (
            <button
              type="button"
              data-testid={view.control.kind === 'stop' ? 'runner-stop' : 'runner-start'}
              disabled={busy}
              onClick={() => { void (view.control.kind === 'stop' ? stop() : start()); }}
              className={`w-full px-3 py-2 rounded text-sm font-medium transition-colors disabled:opacity-60 disabled:cursor-not-allowed ${
                view.control.kind === 'stop'
                  ? 'border border-red-700 bg-red-900/40 hover:bg-red-900/60 text-red-100'
                  : 'border border-emerald-700 bg-emerald-900/40 hover:bg-emerald-900/60 text-emerald-100'
              }`}
            >
              {action === 'starting' ? 'Starting…' : action === 'stopping' ? 'Stopping…' : view.control.label}
            </button>
          )}
          {view.control.kind === 'none' && view.control.unavailableReason && (
            <p className="text-sm text-amber-200" data-testid="runner-control-unavailable">
              {view.control.unavailableReason}
            </p>
          )}
          {actionNote && (
            <p className="mt-2 text-sm text-gray-300" data-testid="runner-action-note">{actionNote}</p>
          )}
          {/* The only surviving home of the pasted command: the console tried,
              and could not. Now it is a genuine remedy rather than a chore. */}
          {failureCommand && (
            <div className="mt-2 rounded border border-gray-600 bg-gray-900 px-2 py-1.5 flex items-center justify-between gap-2">
              <code className="text-sm text-gray-300 break-all select-all">{failureCommand}</code>
              <button
                type="button"
                onClick={() => { void copyCommand(); }}
                className="shrink-0 px-2 py-1 text-sm rounded border border-gray-600 bg-gray-700 hover:bg-gray-600 text-gray-200 transition-colors"
              >
                {copied ? 'Copied' : 'Copy'}
              </button>
            </div>
          )}
        </div>
      )}
    </span>
  );
}

export default RunnerHealthIndicator;
