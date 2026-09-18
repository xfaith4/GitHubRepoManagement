/**
 * Release 3.2 milestone 1 — the background scan, observable and cancellable.
 *
 * Renders nothing until there is something true to say: a running scan shows
 * its phase and repo count with a Cancel control; a scan that ended abnormally
 * (cancelled / failed / aborted) keeps a short-lived note so the outcome is
 * seen rather than inferred from silence; a completed scan says nothing here —
 * the grid's own scan meta already carries its counts.
 *
 * Cancel is honored at the worker's next phase boundary, so the button flips
 * to a disabled "Cancelling…" with the reason in its title instead of
 * pretending the stop is instant.
 */
import { useRef, useState } from 'react';
import { getPortfolioScanStatus, cancelPortfolioScan } from '../services/apiClient';
import { usePollLoop } from '../hooks/usePollLoop';
import type { BackgroundScanStatus } from '../types';

const RUNNING_POLL_MS = 2500;
const IDLE_POLL_MS = 10000;
/** How long an abnormal outcome stays visible after its last update. */
const TERMINAL_NOTE_MS = 5 * 60 * 1000;

const ScanProgressChip = () => {
  const [status, setStatus] = useState<BackgroundScanStatus | null>(null);
  const [cancelPending, setCancelPending] = useState(false);
  // Sampled per poll rather than in render: the render must stay pure, and a
  // note whose expiry is only re-judged every poll tick is precise enough.
  const [nowMs, setNowMs] = useState(0);

  // Lane 0.21 — the poll helper owns the chain: a running scan is sampled
  // fast, an idle host slowly, and a slow or failing host backs the loop off.
  const runningRef = useRef(false);
  usePollLoop(async (signal) => {
    let next: BackgroundScanStatus | null = null;
    let failure: unknown = null;
    try {
      next = await getPortfolioScanStatus({ signal });
    } catch (error) {
      // A status probe that fails is silence, not an alarm; the helper backs
      // off and the next tick retries. The assessment panels carry their own
      // error states.
      failure = error;
    }
    if (signal.aborted) return;
    setNowMs(Date.now());
    if (next) {
      setStatus(next);
      runningRef.current = next.state === 'running';
      if (next.state !== 'running') setCancelPending(false);
    }
    if (failure) throw failure;
  }, { intervalMs: () => (runningRef.current ? RUNNING_POLL_MS : IDLE_POLL_MS) });

  const handleCancel = async () => {
    setCancelPending(true);
    try {
      await cancelPortfolioScan();
    } catch {
      // The named no-scan-running refusal means the scan ended between our
      // last poll and the click — the next poll renders that truth.
      setCancelPending(false);
    }
  };

  if (!status || status.state === 'never-run' || status.state === 'completed') return null;

  if (status.state === 'running') {
    const repoPart = status.reposTotal != null
      ? `${status.reposDone ?? 0}/${status.reposTotal} repos`
      : status.reposDone != null
        ? `${status.reposDone} repos`
        : 'starting';
    const cancelInFlight = cancelPending || status.cancelRequested;
    return (
      <span className="inline-flex items-center gap-2 text-xs text-gray-400" role="status" aria-live="polite">
        <span className="inline-block w-1.5 h-1.5 rounded-full bg-indigo-400 animate-pulse" />
        <span>
          Scanning — {status.phase ?? 'starting'} ({repoPart}, phase {Math.min(status.phasesDone + 1, status.phaseTotal)}/{status.phaseTotal})
        </span>
        <button
          type="button"
          onClick={handleCancel}
          disabled={cancelInFlight}
          aria-label="Cancel portfolio scan"
          title={cancelInFlight
            ? 'Cancel already requested; the scan stops at its next phase boundary.'
            : 'Stop the background scan at its next phase boundary. Completed phases keep their results.'}
          className={`px-1.5 py-0.5 rounded border text-xs ${cancelInFlight
            ? 'border-gray-700 text-gray-600 cursor-not-allowed'
            : 'border-gray-600 text-gray-300 hover:border-red-500 hover:text-red-400'}`}
        >
          {cancelInFlight ? 'Cancelling…' : 'Cancel'}
        </button>
      </span>
    );
  }

  // Abnormal terminal states: visible briefly, then quiet.
  const updatedAtMs = status.updatedAt ? new Date(status.updatedAt).getTime() : 0;
  if (!updatedAtMs || !nowMs || nowMs - updatedAtMs > TERMINAL_NOTE_MS) return null;

  const noteText = status.state === 'cancelled'
    ? `Scan cancelled (${status.phasesDone}/${status.phaseTotal} phases kept)`
    : status.state === 'failed'
      ? 'Scan failed'
      : 'Scan aborted';
  const noteTitle = status.state === 'failed' && status.error
    ? status.error
    : status.state === 'aborted'
      ? 'The scan worker died without finishing; its last progress write is shown. Start a new scan to recover.'
      : 'Results from phases that completed before the cancel are kept; nothing partial was invented.';

  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-amber-500" role="status" title={noteTitle}>
      <span className="inline-block w-1.5 h-1.5 rounded-full bg-amber-500" />
      {noteText}
    </span>
  );
};

export default ScanProgressChip;
