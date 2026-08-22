import React, { useCallback, useEffect, useState } from 'react';
import { getRunnerPresence } from '../services/apiClient';
import { resolveRunnerPresence, runnerStartCommand, type RunnerPresencePayload } from '../lib/runnerPresence';

/**
 * Release 3.5 milestone 6 — runner health beside `Backend: Online`, above the
 * fold on every tab.
 *
 * The review's sharpest Tier-3 finding: the single most consequential message
 * in the app ("Runner stalled: nothing would pick this up…") rendered as red
 * text below the fold while the header cheerfully said `6 active`. The system
 * knew it was broken and told you only if you scrolled. This pill is the
 * above-the-fold delivery: severity-colored, alarming on day-old queued work
 * even when the runner is present, and one click from the remedy command with
 * a copy button.
 */
const POLL_MS = 30_000;

function RunnerHealthIndicator() {
  const [payload, setPayload] = useState<RunnerPresencePayload | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    let cancelled = false;
    const poll = async () => {
      try {
        const data = await getRunnerPresence();
        if (!cancelled) { setPayload(data); setLoaded(true); }
      } catch {
        if (!cancelled) { setPayload(null); setLoaded(true); }
      }
    };
    void poll();
    const timer = setInterval(poll, POLL_MS);
    return () => { cancelled = true; clearInterval(timer); };
  }, []);

  const view = resolveRunnerPresence(payload);

  // The host's absolute form, so the paste works from an elevated terminal
  // that opened in the user profile — not only from a shell already in the repo.
  const copyCommand = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(runnerStartCommand(payload));
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard can be unavailable (permissions, non-secure context); the
      // command stays visible as selectable text either way.
    }
  }, [payload]);

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
          {view.severity !== 'ok' && (
            <div className="rounded border border-gray-600 bg-gray-900 px-2 py-1.5 flex items-center justify-between gap-2">
              <code className="text-[11px] text-gray-300 break-all select-all">{runnerStartCommand(payload)}</code>
              <button
                type="button"
                onClick={() => { void copyCommand(); }}
                className="shrink-0 px-2 py-1 text-[11px] rounded border border-gray-600 bg-gray-700 hover:bg-gray-600 text-gray-200 transition-colors"
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
