import React from 'react';
import useRunnerControl from '../hooks/useRunnerControl';
import { SpinnerIcon } from './icons';

/**
 * Lane 0.20 — the single pane of glass.
 *
 * Before this, judging whether the portfolio was actually being worked meant
 * assembling it: the header pill for the runner, the Work Queue tab for the
 * backlog, and an inference in the operator's head to join them. The two facts
 * that matter together — is anything executing, and what is waiting — arrive on
 * the same route and had never been rendered in the same place.
 *
 * It carries the kill switch for the same reason. A control to halt work
 * belongs where the work is visible; put somewhere else, it asks the operator
 * to decide blind. This is control WITHOUT a bottleneck: execution proceeds
 * unattended by default, and stopping it is one deliberate press rather than
 * per-step authorisation.
 */

function Stat({ label, value, tone = 'neutral' }: { label: string; value: string; tone?: 'neutral' | 'warn' | 'good' }) {
  const valueTone =
    tone === 'warn' ? 'text-amber-300' : tone === 'good' ? 'text-emerald-300' : 'text-gray-100';
  return (
    <div className="rounded border border-gray-700 bg-gray-900/50 px-3 py-2">
      <div className="text-sm text-gray-400">{label}</div>
      <div className={`text-lg font-semibold tabular-nums ${valueTone}`}>{value}</div>
    </div>
  );
}

/** Relative age of the oldest queued entry, or null when nothing is waiting. */
function describeOldest(oldestQueuedAt: string | null | undefined, nowMs: number): string | null {
  if (!oldestQueuedAt) return null;
  const queued = Date.parse(oldestQueuedAt);
  if (Number.isNaN(queued)) return null;
  const minutes = Math.max(0, Math.floor((nowMs - queued) / 60_000));
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return `${hours}h`;
  return `${Math.floor(hours / 24)}d`;
}

const RunnerControlPanel: React.FC = () => {
  const { payload, view, readAtMs, loaded, action, actionNote, failureCommand, start, stop, refresh } = useRunnerControl();

  const queuedTotal = Number(payload?.queuedTotal ?? 0);
  const claimed = Number(payload?.claimedCount ?? 0);
  const stranded = Number(payload?.strandedCount ?? 0);
  // The clock from the fetch, not from this render: reading the clock during
  // render is impure, and an age measured against a later `now` than the
  // payload would report a number the payload never claimed.
  const oldest = describeOldest(payload?.oldestQueuedAt, readAtMs);
  // A lone in-flight flag: the only reason this control disables is the one the
  // label is already saying ("Stopping…"). A compound expression here would be a
  // precondition the operator never gets told about.
  const busy = action !== 'idle';
  const runnerHost = [payload?.hostname, payload?.user].filter(Boolean).join('\\');

  const severityBorder: Record<string, string> = {
    ok: 'border-emerald-700/70',
    warning: 'border-amber-600/70',
    error: 'border-red-700/70',
    unknown: 'border-gray-700',
  };

  return (
    <section
      data-testid="runner-control-panel"
      className={`bg-gray-800/60 border rounded-lg px-4 py-4 ${severityBorder[view.severity] ?? severityBorder.unknown}`}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="text-lg font-semibold text-gray-100">Execution right now</h3>
          <p className="text-sm text-gray-400 mt-0.5">
            Whether anything is working the queue, and what is waiting for it.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => { void refresh(); }}
            className="px-2.5 py-1.5 text-sm rounded border border-gray-600 bg-gray-700 hover:bg-gray-600 text-gray-200 transition-colors"
          >
            Refresh
          </button>
          {view.control.kind !== 'none' && (
            <button
              type="button"
              data-testid={view.control.kind === 'stop' ? 'runner-panel-stop' : 'runner-panel-start'}
              disabled={busy}
              onClick={() => { void (view.control.kind === 'stop' ? stop() : start()); }}
              className={`px-3 py-1.5 rounded text-sm font-medium transition-colors disabled:opacity-60 disabled:cursor-not-allowed ${
                view.control.kind === 'stop'
                  ? 'border border-red-700 bg-red-900/40 hover:bg-red-900/60 text-red-100'
                  : 'border border-emerald-700 bg-emerald-900/40 hover:bg-emerald-900/60 text-emerald-100'
              }`}
            >
              {action === 'starting' ? 'Starting…' : action === 'stopping' ? 'Stopping…' : view.control.label}
            </button>
          )}
        </div>
      </div>

      <p className="mt-3 text-sm text-gray-200 flex items-center gap-2" data-testid="runner-panel-detail">
        {!loaded && <SpinnerIcon className="w-4 h-4 animate-spin text-gray-400" />}
        <span className="font-medium">{view.label}.</span>
        <span className="text-gray-300">{view.detail}</span>
      </p>

      <div className="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-2">
        <Stat label="Queued" value={String(queuedTotal)} tone={queuedTotal > 0 && stranded > 0 ? 'warn' : 'neutral'} />
        <Stat label="Claimable now" value={String(claimed)} tone={claimed > 0 ? 'good' : 'neutral'} />
        <Stat label="Waiting, nothing to claim" value={String(stranded)} tone={stranded > 0 ? 'warn' : 'neutral'} />
        <Stat label="Oldest queued" value={oldest ?? '—'} tone={view.queueAgeAlarmHours != null ? 'warn' : 'neutral'} />
      </div>

      {view.queuedByProviderSummary && (
        <p className="mt-2 text-sm text-gray-300" data-testid="runner-panel-by-provider">
          Backlog by provider: {view.queuedByProviderSummary}
        </p>
      )}

      {/* Attribution for a live runner, so "present" is checkable rather than
          taken on faith — the pid is what an operator needs to look it up. */}
      {view.severity === 'ok' && runnerHost && (
        <p className="mt-2 text-sm text-gray-400" data-testid="runner-panel-identity">
          {runnerHost}
          {payload?.pid ? ` · pid ${payload.pid}` : ''}
          {payload?.mode ? ` · ${payload.mode}` : ''}
          {payload?.secondsSinceBeat != null ? ` · heartbeat ${Math.round(Number(payload.secondsSinceBeat))}s ago` : ''}
        </p>
      )}

      {view.control.kind === 'none' && view.control.unavailableReason && (
        <p className="mt-2 text-sm text-amber-200" data-testid="runner-panel-unavailable">
          {view.control.unavailableReason}
        </p>
      )}

      {actionNote && (
        <p className="mt-3 text-sm text-gray-200 rounded border border-gray-700 bg-gray-900/60 px-3 py-2" data-testid="runner-panel-note">
          {actionNote}
        </p>
      )}

      {failureCommand && (
        <div className="mt-2 rounded border border-gray-600 bg-gray-900 px-3 py-2">
          <p className="text-sm text-gray-400 mb-1">The console could not start it. Run this in your own session:</p>
          <code className="text-sm text-gray-200 break-all select-all">{failureCommand}</code>
        </div>
      )}
    </section>
  );
};

export default RunnerControlPanel;
