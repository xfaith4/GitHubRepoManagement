// Agent Ops (2026-09-27) — layout 1a "Command": actions left, live work
// centre, feed right; the phase roll-up above, completions and repo progress
// below, a run drawer on the right, and the one control that stops all of it.
//
// Data arrives as props from Dashboard's single useAgentOpsData instance, so
// the tab badge and this view can never disagree. Every derivation is in
// lib/agentOps.ts; this file renders and performs actions.
//
// Consequence styling (docs/reference/status-vocabulary.md): read-only
// controls render neutral; controls that start or write something carry the
// amber emphasis and say what they commit you to; the stop family is red.
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import type { AgentOpsData } from '../hooks/useAgentOpsData';
import type { AgentRunEvent, MergeReadinessResult } from '../types';
import { resolveDispatchGate, resolveRunnerPresence } from '../lib/runnerPresence';
import { useDialogDismiss } from '../hooks/useDialogDismiss';
import {
  approveAgentRun,
  approvePackagedItem,
  cancelExecutionTask,
  executeMergeReadinessMerge,
  getAgentRunDetail,
  getMergeReadiness,
  refreshAgentRun,
  rejectPackagedItem,
  startRunner,
  stopRunner,
  type RunnerInterruptedRun,
} from '../services/apiClient';
import {
  DELIVERY_STATES,
  buildActivityFeed,
  buildRepoProgress,
  countByStage,
  deriveOperatorActions,
  describeHeldBanner,
  describeStopSummary,
  formatAgo,
  parseMs,
  selectCurrentPhase,
  selectInFlight,
  selectInterruptible,
  selectNextUp,
  selectRecentlyCompleted,
  toAgentOpsRun,
  type AgentOpsRun,
  type OperatorAction,
  type OperatorActionButton,
  type OperatorActionOp,
  type RunTone,
} from '../lib/agentOps';
import { RefreshIcon, SpinnerIcon } from './icons';

// ── Icons (Phosphor shapes, inline; the portal has no icon font) ───────────

const Svg: React.FC<{ className?: string; children: React.ReactNode; title?: string }> = ({ className = 'w-4 h-4', children, title }) => (
  <svg className={className} viewBox="0 0 256 256" fill="currentColor" aria-hidden={title ? undefined : true} role={title ? 'img' : undefined}>
    {title ? <title>{title}</title> : null}
    {children}
  </svg>
);
const HandIcon: React.FC<{ className?: string }> = ({ className }) => (
  <Svg className={className}><path d="M188,48a27.75,27.75,0,0,0-12,2.71V44a28,28,0,0,0-54.65-8.6A28,28,0,0,0,80,60v64l-3.82-6.13A28,28,0,0,0,27.6,145.73l40.7,74.31A8,8,0,0,0,82,224h71.58a56,56,0,0,0,55.38-48l6.94-60.06c0-.29,0-.59,0-.89V76A28,28,0,0,0,188,48Zm12,66.1c0,.3,0,.59-.05.89L193.09,175A40,40,0,0,1,153.58,208H86.76l-38.06-69.6a12,12,0,0,1,20.5-12.36l19.35,31.14A8,8,0,0,0,104,152V60a12,12,0,0,1,24,0v60a8,8,0,0,0,16,0V44a12,12,0,0,1,24,0v76a8,8,0,0,0,16,0V76a12,12,0,0,1,24,0Z" /></Svg>
);
const SealCheckIcon: React.FC<{ className?: string }> = ({ className }) => (
  <Svg className={className}><path d="M225.86,102.82c-3.77-3.94-7.67-8-9.14-11.57-1.36-3.27-1.44-8.69-1.52-13.94-.15-9.76-.31-20.82-8-28.51s-18.75-7.85-28.51-8c-5.25-.08-10.67-.16-13.94-1.52-3.56-1.47-7.63-5.37-11.57-9.14C146.28,23.51,138.44,16,128,16s-18.27,7.51-25.18,14.14c-3.94,3.77-8,7.67-11.57,9.14C88,40.64,82.56,40.72,77.31,40.8c-9.76.15-20.82.31-28.51,8S41,67.55,40.8,77.31c-.08,5.25-.16,10.67-1.52,13.94-1.47,3.56-5.37,7.63-9.14,11.57C23.51,109.72,16,117.56,16,128s7.51,18.27,14.14,25.18c3.77,3.94,7.67,8,9.14,11.57,1.36,3.27,1.44,8.69,1.52,13.94.15,9.76.31,20.82,8,28.51s18.75,7.85,28.51,8c5.25.08,10.67.16,13.94,1.52,3.56,1.47,7.63,5.37,11.57,9.14C109.72,232.49,117.56,240,128,240s18.27-7.51,25.18-14.14c3.94-3.77,8-7.67,11.57-9.14,3.27-1.36,8.69-1.44,13.94-1.52,9.76-.15,20.82-.31,28.51-8s7.85-18.75,8-28.51c.08-5.25.16-10.67,1.52-13.94,1.47-3.56,5.37-7.63,9.14-11.57C232.49,146.28,240,138.44,240,128S232.49,109.73,225.86,102.82Zm-52.2,6.84-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,148.69l50.34-50.35a8,8,0,0,1,11.32,11.32Z" /></Svg>
);
const GitMergeIcon: React.FC<{ className?: string }> = ({ className }) => (
  <Svg className={className}><path d="M208,144a32,32,0,0,0-31,24H160c-27.66,0-38-13-46.1-27.41A64,64,0,0,0,104,112H96a32,32,0,1,0-16,0V144a32,32,0,1,0,16,0V128a48.07,48.07,0,0,1,28.53,15.35C137.5,161.34,152.13,184,160,184h17a32,32,0,1,0,31-40ZM72,80a16,16,0,1,1,16,16A16,16,0,0,1,72,80Zm32,96a16,16,0,1,1-16-16A16,16,0,0,1,104,176Zm104,16a16,16,0,1,1,16-16A16,16,0,0,1,208,192Z" /></Svg>
);
const WarningCircleIcon: React.FC<{ className?: string }> = ({ className }) => (
  <Svg className={className}><path d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm0,192a88,88,0,1,1,88-88A88.1,88.1,0,0,1,128,216Zm-8-80V80a8,8,0,0,1,16,0v56a8,8,0,0,1-16,0Zm20,36a12,12,0,1,1-12-12A12,12,0,0,1,140,172Z" /></Svg>
);
const PackageIcon: React.FC<{ className?: string }> = ({ className }) => (
  <Svg className={className}><path d="M223.68,66.15,135.68,18a15.88,15.88,0,0,0-15.36,0l-88,48.17a16,16,0,0,0-8.32,14v95.64a16,16,0,0,0,8.32,14l88,48.17a15.88,15.88,0,0,0,15.36,0l88-48.17a16,16,0,0,0,8.32-14V80.18A16,16,0,0,0,223.68,66.15ZM128,32l80.34,44-29.77,16.3-80.35-44ZM128,120,47.66,76l33.9-18.56,80.34,44ZM40,90l80,43.78v85.79L40,175.82Zm176,85.78h0l-80,43.79V133.82l32-17.51V152a8,8,0,0,0,16,0V107.55L216,90v85.77Z" /></Svg>
);
const PlayIcon: React.FC<{ className?: string }> = ({ className }) => (
  <Svg className={className}><path d="M232.4,114.49,88.32,26.35a16,16,0,0,0-16.2-.3A15.86,15.86,0,0,0,64,39.87V216.13A15.94,15.94,0,0,0,80,232a16.07,16.07,0,0,0,8.36-2.35L232.4,141.51a15.81,15.81,0,0,0,0-27ZM80,215.94V40l143.83,88Z" /></Svg>
);
const XIcon: React.FC<{ className?: string }> = ({ className }) => (
  <Svg className={className}><path d="M205.66,194.34a8,8,0,0,1-11.32,11.32L128,139.31,61.66,205.66a8,8,0,0,1-11.32-11.32L116.69,128,50.34,61.66A8,8,0,0,1,61.66,50.34L128,116.69l66.34-66.35a8,8,0,0,1,11.32,11.32L139.31,128Z" /></Svg>
);
const ArrowSquareOutIcon: React.FC<{ className?: string }> = ({ className }) => (
  <Svg className={className}><path d="M224,104a8,8,0,0,1-16,0V59.32l-66.33,66.34a8,8,0,0,1-11.32-11.32L196.68,48H152a8,8,0,0,1,0-16h64a8,8,0,0,1,8,8Zm-40,24a8,8,0,0,0-8,8v72H48V80h72a8,8,0,0,0,0-16H48A16,16,0,0,0,32,80V208a16,16,0,0,0,16,16H176a16,16,0,0,0,16-16V136A8,8,0,0,0,184,128Z" /></Svg>
);

// ── Styling tables ─────────────────────────────────────────────────────────

const TAG_TONE: Record<RunTone, string> = {
  bad: 'bg-status-crit/20 text-status-crit-text',
  wait: 'bg-text/8 text-text/70',
  operator: 'bg-accent-700 text-accent-100',
  landed: 'bg-text/8 text-text/85',
  intake: 'bg-text/8 text-text/70',
  active: 'bg-accent-800 text-accent-200',
  cancelled: 'bg-text/6 text-text/50',
};

const BUTTON_BASE = 'inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-[13px] leading-5 transition-colors disabled:opacity-60 disabled:cursor-not-allowed';
const BUTTON_NEUTRAL = `${BUTTON_BASE} border-text/18 text-text/80 hover:text-text hover:border-text/35`;
const BUTTON_CONSEQUENCE = `${BUTTON_BASE} border-status-warn/60 bg-status-warn/15 text-status-warn-text hover:bg-status-warn/25`;
const BUTTON_DESTRUCTIVE = `${BUTTON_BASE} border-status-crit/70 bg-status-crit/15 text-status-crit-text hover:bg-status-crit/25`;

function buttonClass(button: Pick<OperatorActionButton, 'consequence' | 'destructive'>): string {
  if (button.destructive) return BUTTON_DESTRUCTIVE;
  return button.consequence ? BUTTON_CONSEQUENCE : BUTTON_NEUTRAL;
}

const KIND_ICON: Record<OperatorAction['kind'], React.FC<{ className?: string }>> = {
  'runner-held': HandIcon,
  'approve-sha': SealCheckIcon,
  merge: GitMergeIcon,
  'ci-failed': WarningCircleIcon,
  'package-approval': PackageIcon,
};

const KIND_TONE: Record<OperatorAction['tone'], string> = {
  crit: 'text-status-crit-text',
  accent: 'text-accent-300',
  neutral: 'text-text/60',
};

const STAGE_BAR: Record<string, string> = {
  intake: 'bg-text/25',
  sched: 'bg-accent-800',
  agent: 'bg-accent-500',
  ci: 'bg-accent-600',
  op: 'bg-accent-400',
  landed: 'bg-text/25',
};

function segmentClass(row: AgentOpsRun, i: number): string {
  if (i < row.index) return 'bg-accent-600';
  if (i === row.index) {
    if (row.tone === 'bad') return 'bg-status-crit';
    if (row.tone === 'wait') return 'bg-text/40';
    return 'bg-accent-300';
  }
  return 'bg-text/10';
}

const StateTag: React.FC<{ row: Pick<AgentOpsRun, 'stateLabel' | 'tone'>; className?: string }> = ({ row, className = '' }) => (
  <span className={`inline-block rounded px-1.5 py-0.5 text-[10px] font-medium tracking-wide whitespace-nowrap ${TAG_TONE[row.tone]} ${className}`}>{row.stateLabel}</span>
);

const SectionTitle: React.FC<{ children: React.ReactNode; count?: number; countTone?: 'accent' | 'neutral'; trailing?: React.ReactNode }> = ({ children, count, countTone = 'neutral', trailing }) => (
  <div className="flex items-center gap-2">
    <h3 className="m-0 text-[13px] font-medium uppercase tracking-wide text-text/85">{children}</h3>
    {typeof count === 'number' ? (
      <span className={`rounded px-1.5 py-0.5 text-[11px] tabular-nums ${countTone === 'accent' ? 'bg-accent-800 text-accent-100' : 'bg-text/8 text-text/70'}`}>{count}</span>
    ) : null}
    {trailing ? <span className="ml-auto text-[11px] text-text/55">{trailing}</span> : null}
  </div>
);

// ── The view ───────────────────────────────────────────────────────────────

interface RefusalNote {
  actionId: string;
  message: string;
}

interface LastStop {
  interrupted: RunnerInterruptedRun[];
  /** Set when the host predates mid-run interrupts and runs were cancelled in the ledger instead. */
  fallbackNote: string | null;
}

export interface AgentOpsViewProps {
  data: AgentOpsData;
  /** Injected clock for tests; production reads Date.now() every 10 s. */
  nowMs?: number;
}

const AgentOpsView: React.FC<AgentOpsViewProps> = ({ data, nowMs: fixedNow }) => {
  const [tickNow, setTickNow] = useState(() => Date.now());
  useEffect(() => {
    if (fixedNow != null) return;
    const id = window.setInterval(() => setTickNow(Date.now()), 10_000);
    return () => window.clearInterval(id);
  }, [fixedNow]);
  const nowMs = fixedNow ?? Math.max(tickNow, data.updatedAtMs);

  const rows = useMemo(() => data.runs.map(toAgentOpsRun), [data.runs]);
  const inFlight = useMemo(() => selectInFlight(rows), [rows]);
  const recent = useMemo(() => selectRecentlyCompleted(rows), [rows]);
  const nextUp = useMemo(() => selectNextUp(data.queue), [data.queue]);
  const actions = useMemo(
    () => deriveOperatorActions({ rows, packages: data.packages, runner: data.runner, nowMs }),
    [rows, data.packages, data.runner, nowMs],
  );
  const feed = useMemo(() => buildActivityFeed(rows, data.runner), [rows, data.runner]);
  const stageCounts = useMemo(() => countByStage(rows, nowMs), [rows, nowMs]);
  const repoProgress = useMemo(() => buildRepoProgress(data.roadmap, rows), [data.roadmap, rows]);
  const phase = useMemo(() => selectCurrentPhase(data.roadmap, rows), [data.roadmap, rows]);
  const victims = useMemo(() => selectInterruptible(rows), [rows]);
  const runnerView = useMemo(() => resolveRunnerPresence(data.runner, data.updatedAtMs || nowMs), [data.runner, data.updatedAtMs, nowMs]);
  const held = data.runner?.stoppedByOperator === true;
  // Approving a package queues work. The Release 3.1 gate applies here as on
  // every other surface that queues: with no runner to claim it, the control
  // renders disabled and names the unmet precondition rather than offering a
  // button the host answers with 409.
  const dispatchGate = useMemo(() => resolveDispatchGate(data.runner), [data.runner]);

  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);
  const [stopDialogOpen, setStopDialogOpen] = useState(false);
  const [stopReason, setStopReason] = useState('');
  const [stopBusy, setStopBusy] = useState(false);
  const [stopError, setStopError] = useState<string | null>(null);
  const [lastStop, setLastStop] = useState<LastStop | null>(null);
  const [pendingActionId, setPendingActionId] = useState<string | null>(null);
  const [refusal, setRefusal] = useState<RefusalNote | null>(null);

  // Derived, not synced: a run that left the list (cancelled, aged out) simply
  // has no row, so its drawer stops rendering without an effect resetting state.
  const selectedRow = selectedRunId ? rows.find(r => r.id === selectedRunId) ?? null : null;

  const runAction = useCallback(async (actionId: string, op: OperatorActionOp) => {
    if (op.type === 'details') { setSelectedRunId(op.runId); return; }
    setPendingActionId(actionId);
    setRefusal(null);
    try {
      switch (op.type) {
        case 'resume': await startRunner(); break;
        case 'approve': await approveAgentRun(op.runId, op.sha); break;
        case 'merge': await executeMergeReadinessMerge(op.repoId); break;
        case 'refresh': await refreshAgentRun(op.runId); break;
        case 'cancel': {
          const result = await cancelExecutionTask(op.repoName, 'Cancelled from Agent Ops');
          if (!result.success) throw new Error(result.error ?? 'The cancel was refused.');
          break;
        }
        case 'approve-package': await approvePackagedItem(op.packetId); break;
        case 'reject-package': await rejectPackagedItem(op.packetId, 'Rejected from Agent Ops'); break;
      }
      data.refresh();
    } catch (error) {
      // The host's refusal text, verbatim: a 409 carries the rule and remedy.
      setRefusal({ actionId, message: error instanceof Error ? error.message : String(error) });
    } finally {
      setPendingActionId(null);
    }
  }, [data]);

  const confirmStop = useCallback(async () => {
    setStopBusy(true);
    setStopError(null);
    const reason = stopReason.trim() || 'All work stop';
    try {
      const result = await stopRunner(reason, { interrupt: true });
      let fallbackNote: string | null = null;
      let interrupted: RunnerInterruptedRun[] = Array.isArray(result.interrupted) ? result.interrupted : [];
      if (!Array.isArray(result.interrupted)) {
        // An older host held the runners but cannot reach a run in flight:
        // cancel each active repo in the ledger and say that is what happened.
        const cancelled: RunnerInterruptedRun[] = [];
        for (const victim of victims) {
          const outcome = await cancelExecutionTask(victim.repo, reason);
          if (outcome.success) cancelled.push({ runId: victim.id, repoName: victim.repo, provider: victim.provider, fromState: victim.state, remote: false });
        }
        interrupted = cancelled;
        fallbackNote = 'This host predates mid-run interrupts: runners are held and the active runs were cancelled in the ledger, but an agent already running finishes its current task.';
      }
      setLastStop({ interrupted, fallbackNote });
      setStopDialogOpen(false);
      setStopReason('');
      data.refresh();
    } catch (error) {
      setStopError(error instanceof Error ? error.message : String(error));
    } finally {
      setStopBusy(false);
    }
  }, [data, stopReason, victims]);

  const closeStopDialog = useCallback(() => { if (!stopBusy) setStopDialogOpen(false); }, [stopBusy]);
  const closeDrawer = useCallback(() => setSelectedRunId(null), []);
  const stopPanelRef = useDialogDismiss<HTMLDivElement>(stopDialogOpen, closeStopDialog);
  const drawerRef = useDialogDismiss<HTMLDivElement>(selectedRow != null, closeDrawer);

  const portfolioDone = repoProgress.reduce((sum, r) => sum + r.done, 0);
  const portfolioTotal = repoProgress.reduce((sum, r) => sum + r.total, 0);

  return (
    <div className="px-4 sm:px-[22px] pb-6 text-text" data-testid="agent-ops-view">
      {/* Header row */}
      <div className="flex flex-wrap items-center gap-x-6 gap-y-3 py-4">
        <div className="mr-auto flex items-center gap-3">
          <GitMergeIcon className="w-[22px] h-[22px] text-accent" />
          <div className="flex flex-col">
            <span className="text-[17px] font-medium leading-tight">Agent Operations</span>
            <span className="text-[11px] text-text/55">
              {data.roadmap.length > 0 ? `${data.roadmap.length} repositories in the roadmap index` : 'Roadmap index not loaded yet'}
            </span>
          </div>
        </div>
        <div className="flex items-center gap-2 text-[13px]" data-testid="agent-ops-runner">
          <span
            className={`inline-block w-2 h-2 rounded-full ${
              held ? 'bg-status-crit' : runnerView.severity === 'ok' ? 'bg-accent' : runnerView.severity === 'warning' ? 'bg-status-warn' : runnerView.severity === 'error' ? 'bg-status-crit' : 'bg-text/40'
            }`}
            aria-hidden="true"
          />
          <span>{runnerView.label}</span>
          <span className="hidden md:inline text-text/55">{runnerView.detail}</span>
        </div>
        <span className="text-[12px] text-text/55" aria-live="polite">
          {data.loaded ? `Updated ${formatAgo(data.updatedAtMs, nowMs)}` : 'Loading…'}
          {data.error ? <span className="ml-2 text-status-warn-text" title={data.error}>· last poll failed; showing the last answer</span> : null}
        </span>
        <button type="button" className={BUTTON_NEUTRAL} onClick={() => data.refresh()}>
          <RefreshIcon className="w-4 h-4" />
          Refresh
        </button>
        {held ? (
          <button
            type="button"
            className={BUTTON_CONSEQUENCE}
            onClick={() => { void runAction('runner-held', { type: 'resume' }); }}
            disabled={pendingActionId === 'runner-held'}
            title={pendingActionId === 'runner-held' ? 'Resume request in flight' : 'Releases the hold, requeues interrupted runs and asks the scheduled task to start a runner'}
          >
            {pendingActionId === 'runner-held' ? <SpinnerIcon className="w-4 h-4" /> : <PlayIcon className="w-4 h-4" />}
            Resume runners
          </button>
        ) : (
          <button
            type="button"
            className={`${BUTTON_DESTRUCTIVE} h-9 px-4`}
            onClick={() => { setStopError(null); setStopDialogOpen(true); }}
            title="Hold every runner and interrupt the runs in flight. Nothing is pushed or merged."
          >
            <HandIcon className="w-4 h-4" />
            All work stop
          </button>
        )}
      </div>

      {/* Held banner */}
      {held && data.runner ? (
        <div className="-mx-4 sm:-mx-[22px] mb-4 flex flex-col gap-2 bg-status-crit/15 px-4 sm:px-[22px] py-3 text-[13px] text-status-crit-text" role="status" data-testid="agent-ops-held-banner">
          <div className="flex items-center gap-3">
            <HandIcon className="w-4 h-4 shrink-0" />
            <span>{describeHeldBanner(data.runner, nowMs)}</span>
          </div>
          {lastStop && lastStop.interrupted.length > 0 ? (
            <ul className="ml-7 flex flex-wrap gap-2 text-[12px]">
              {lastStop.interrupted.map(item => (
                <li key={item.runId} className="rounded bg-status-crit/15 px-2 py-0.5">
                  {item.repoName} · {item.provider}{item.fromState ? ` · from ${item.fromState}` : ''}{item.remote ? ' · remote; will finish on GitHub, not merged' : ''}
                </li>
              ))}
            </ul>
          ) : null}
          {lastStop?.fallbackNote ? <p className="ml-7 m-0 text-[12px] text-text/70">{lastStop.fallbackNote}</p> : null}
        </div>
      ) : null}

      {/* Phase roll-up band */}
      <div className="grid grid-cols-1 lg:grid-cols-[320px_minmax(0,1fr)] gap-6 lg:gap-8 py-4 border-b border-divider">
        <div className="flex flex-col gap-1" data-testid="agent-ops-phase">
          <span className="text-[10px] font-medium uppercase tracking-[0.08em] text-text/55">
            Current phase{phase ? ` · ${phase.repo}` : ''}
          </span>
          {phase ? (
            <>
              <span className="text-[20px] font-medium leading-[1.2]">{phase.title}</span>
              <div className="mt-2 flex items-baseline gap-3">
                <span className="text-[48px] font-medium leading-none tracking-[-0.03em] tabular-nums">{phase.pct}%</span>
                <span className="text-[13px] text-text/55">
                  {phase.done} of {phase.total} items{phase.phaseName ? ` · ${phase.phaseName}` : ''}
                </span>
              </div>
              <div className="mt-2 h-1 overflow-hidden rounded-xs bg-text/10">
                <div className="h-full bg-accent" style={{ width: `${phase.pct}%` }} />
              </div>
              {phase.nextItem ? <span className="mt-1 text-[12px] text-text/70 truncate" title={phase.nextItem}>Next: {phase.nextItem}</span> : null}
            </>
          ) : (
            <span className="text-[13px] text-text/55">No roadmap index yet. Run a roadmap scan to see phase progress here.</span>
          )}
        </div>
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-3 sm:grid-cols-6 gap-2">
            {stageCounts.map(stage => (
              <div key={stage.key} className="flex flex-col gap-1" data-testid={`agent-ops-stage-${stage.key}`}>
                <span className="text-[22px] font-medium leading-none tabular-nums">{stage.count}</span>
                <span className="text-[11px] text-text/55">{stage.label}</span>
                <div className={`h-[3px] rounded-xs ${STAGE_BAR[stage.key]}`} />
              </div>
            ))}
          </div>
          <p className="m-0 text-[11px] text-text/45">
            Counts per delivery stage across the last 60 runs. Milestone chips render when the roadmap index reports per-milestone state; today it reports items and the active phase.
          </p>
        </div>
      </div>

      {/* Three columns */}
      <div className="grid grid-cols-1 xl:grid-cols-[380px_minmax(0,1fr)_330px] gap-6 py-5">
        {/* Operator actions */}
        <section className="flex flex-col gap-3 min-w-0" aria-labelledby="agent-ops-actions-title">
          <div id="agent-ops-actions-title"><SectionTitle count={actions.length} countTone="accent">Operator actions</SectionTitle></div>
          {actions.length === 0 ? (
            <p className="m-0 py-3 text-[13px] text-text/55" data-testid="agent-ops-actions-empty">
              Nothing needs you right now. New decisions appear here as runs reach an operator gate.
            </p>
          ) : (
            <ul className="m-0 flex list-none flex-col gap-3 p-0" data-testid="agent-ops-actions">
              {actions.map(action => {
                const Icon = KIND_ICON[action.kind];
                const busy = pendingActionId === action.id;
                const secondary = action.secondary;
                const queuesWork = action.primary.op.type === 'approve-package';
                const gated = queuesWork && !dispatchGate.canQueue;
                return (
                  <li key={action.id} className="flex flex-col gap-2 rounded-lg bg-surface p-3 shadow-sm" data-testid="agent-ops-action" data-kind={action.kind}>
                    <div className="flex items-center gap-2">
                      <Icon className={`w-4 h-4 ${KIND_TONE[action.tone]}`} />
                      <span className={`text-[10px] font-medium uppercase tracking-[0.08em] ${KIND_TONE[action.tone]}`}>{action.kindLabel}</span>
                      <span className="ml-auto text-[11px] text-text/55 truncate">{action.repo}</span>
                    </div>
                    <span className="text-[14px] leading-[1.35]">{action.title}</span>
                    <span className="text-[12px] leading-[1.4] text-text/60">{action.detail}</span>
                    <div className="mt-0.5 flex flex-wrap gap-2">
                      <button
                        type="button"
                        className={buttonClass(action.primary)}
                        onClick={() => { void runAction(action.id, action.primary.op); }}
                        disabled={busy || gated}
                        title={busy ? 'Request in flight' : gated ? dispatchGate.unmetPrecondition : action.detail}
                      >
                        {busy ? <SpinnerIcon className="w-3.5 h-3.5" /> : null}
                        {action.primary.label}
                      </button>
                      {secondary ? (
                        <button
                          type="button"
                          className={buttonClass(secondary)}
                          onClick={() => { void runAction(action.id, secondary.op); }}
                          disabled={busy}
                          title={busy ? 'Request in flight' : secondary.label}
                        >
                          {secondary.label}
                        </button>
                      ) : null}
                    </div>
                    {gated ? (
                      <p className="m-0 text-[12px] text-status-warn-text" data-testid="agent-ops-gate-note">{dispatchGate.unmetPrecondition}</p>
                    ) : null}
                    {refusal?.actionId === action.id ? (
                      <p className="m-0 rounded-md border border-status-crit/45 bg-status-crit/10 px-2 py-1 text-[12px] text-status-crit-text" role="alert">{refusal.message}</p>
                    ) : null}
                  </li>
                );
              })}
            </ul>
          )}
        </section>

        {/* In flight + Next up */}
        <div className="flex min-w-0 flex-col gap-6">
          <section className="flex flex-col gap-3" aria-labelledby="agent-ops-inflight-title">
            <div id="agent-ops-inflight-title"><SectionTitle count={inFlight.length} trailing="20-state delivery strip · DISCOVERED → COMPLETE">In flight</SectionTitle></div>
            {inFlight.length === 0 ? (
              <p className="m-0 py-3 text-[13px] text-text/55" data-testid="agent-ops-inflight-empty">
                {data.loaded ? 'No runs in flight. Approved packages and dispatched items appear here as a runner claims them.' : 'Loading runs…'}
              </p>
            ) : (
              <ul className="m-0 flex list-none flex-col gap-2 p-0">
                {inFlight.map(row => (
                  <li key={row.id}>
                    <button
                      type="button"
                      onClick={() => setSelectedRunId(row.id)}
                      className={`grid w-full grid-cols-[minmax(0,1fr)_auto] gap-x-4 gap-y-2 rounded-lg bg-surface p-3 text-left transition-shadow hover:shadow-[0_0_0_1px_var(--color-accent-700)] ${row.tone === 'bad' ? 'shadow-[0_0_0_1px_var(--color-status-crit)]' : 'shadow-sm'}`}
                      data-testid="agent-ops-run"
                      data-state={row.state}
                      aria-haspopup="dialog"
                    >
                      <div className="flex min-w-0 flex-col gap-0.5">
                        <div className="flex items-center gap-2 text-[11px]">
                          <span className="text-accent-300">{row.repo}</span>
                          <span className="text-text/55">· {row.providerLabel} · attempt {row.attempt}</span>
                        </div>
                        <span className="truncate text-[14px]">{row.title}</span>
                      </div>
                      <div className="flex flex-col items-end gap-0.5">
                        <StateTag row={row} />
                        <span className="text-[11px] text-text/55">{formatAgo(row.updatedMs, nowMs)}</span>
                      </div>
                      <div className="col-span-2 flex gap-0.5" aria-hidden="true">
                        {DELIVERY_STATES.map((state, i) => (
                          <div key={state} className={`h-1 flex-1 rounded-[1px] ${segmentClass(row, i)}`} />
                        ))}
                      </div>
                      <div className="col-span-2 flex flex-wrap gap-x-4 text-[11px] text-text/55">
                        <span>{row.stage.label}</span>
                        <span>{row.prNumber ? `PR #${row.prNumber}` : 'No PR yet'}</span>
                        {row.ciLabel ? <span>{row.ciLabel}</span> : null}
                        <span className="ml-auto truncate max-w-[50%]" title={row.lastEvent}>{row.lastEvent}</span>
                      </div>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="flex flex-col gap-2" aria-labelledby="agent-ops-next-title">
            <div id="agent-ops-next-title"><SectionTitle count={nextUp.length}>Next up</SectionTitle></div>
            {nextUp.length === 0 ? (
              <p className="m-0 py-2 text-[13px] text-text/55">Nothing ranked for dispatch. The Dispatch Board's ranked queue feeds this table.</p>
            ) : (
              <table className="w-full border-collapse text-left">
                <tbody>
                  {nextUp.map(item => (
                    <tr key={`${item.rank}:${item.repo}`} className="border-t border-divider">
                      <td className="w-7 py-1.5 text-[12px] text-text/50 tabular-nums">{item.rank}</td>
                      <td className="py-1.5 text-[13px]">
                        {item.title}
                        <div className="text-[11px] text-text/55">{item.repo}</div>
                      </td>
                      <td className="hidden sm:table-cell w-[90px] py-1.5 text-[12px] text-text/55">{item.providerLabel}</td>
                      <td className="w-[110px] py-1.5 text-right text-[12px] text-text/55 tabular-nums">score {item.score}</td>
                      <td className="w-[110px] py-1.5 text-right"><StateTag row={{ stateLabel: item.state, tone: 'intake' }} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </section>
        </div>

        {/* Live activity */}
        <section className="flex min-w-0 flex-col gap-3" aria-labelledby="agent-ops-feed-title">
          <div id="agent-ops-feed-title" className="flex items-center gap-2">
            <SectionTitle>Live activity</SectionTitle>
            <span className="inline-block w-1.5 h-1.5 rounded-full bg-accent animate-pulse" aria-hidden="true" />
          </div>
          {feed.length === 0 ? (
            <p className="m-0 py-2 text-[13px] text-text/55">No events yet.</p>
          ) : (
            <ol className="m-0 flex list-none flex-col p-0" data-testid="agent-ops-feed">
              {feed.map((event, i) => (
                <li key={`${event.atMs}:${event.runId ?? event.repo}:${i}`} className="grid grid-cols-[14px_minmax(0,1fr)] gap-2 py-1.5">
                  <span className={`mt-1.5 inline-block w-[7px] h-[7px] rounded-full ${event.bad ? 'bg-status-crit' : 'bg-accent-500'}`} aria-hidden="true" />
                  <div className="flex min-w-0 flex-col">
                    <span className="text-[12.5px] leading-[1.4]">{event.message}</span>
                    <span className="text-[11px] text-text/55">{event.repo} · {formatAgo(event.atMs, nowMs)}</span>
                  </div>
                </li>
              ))}
            </ol>
          )}
        </section>
      </div>

      {/* Bottom band */}
      <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)] gap-6 lg:gap-8 border-t border-divider py-5">
        <section className="flex min-w-0 flex-col gap-2" aria-labelledby="agent-ops-recent-title">
          <div id="agent-ops-recent-title"><SectionTitle>Recently completed</SectionTitle></div>
          {recent.length === 0 ? (
            <p className="m-0 py-2 text-[13px] text-text/55">Nothing has landed in the last 60 runs.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full border-collapse text-left">
                <thead>
                  <tr className="text-[11px] uppercase tracking-wide text-text/55">
                    <th className="py-1.5 font-medium">Task</th>
                    <th className="py-1.5 font-medium">Provider</th>
                    <th className="py-1.5 font-medium">PR</th>
                    <th className="py-1.5 font-medium">Diff</th>
                    <th className="py-1.5 text-right font-medium">Finished</th>
                  </tr>
                </thead>
                <tbody>
                  {recent.map(row => (
                    <tr key={row.id} className="cursor-pointer border-t border-divider hover:bg-text/4" onClick={() => setSelectedRunId(row.id)}>
                      <td className="py-1.5 text-[13px]">
                        {row.title}
                        <div className="text-[11px] text-text/55">{row.repo}</div>
                      </td>
                      <td className="py-1.5 text-[12px] text-text/55">{row.providerLabel}</td>
                      <td className="py-1.5 text-[12px]">{row.prNumber ? `PR #${row.prNumber}` : '—'}</td>
                      <td className="py-1.5 text-[12px] text-text/55" title="The run ledger does not report changed-file counts yet">—</td>
                      <td className="py-1.5 text-right">
                        <StateTag row={row} />
                        <div className="text-[11px] text-text/55">{formatAgo(row.updatedMs, nowMs)}</div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <section className="flex min-w-0 flex-col gap-2" aria-labelledby="agent-ops-repos-title">
          <div id="agent-ops-repos-title" className="flex items-baseline gap-2">
            <SectionTitle>Repo progress</SectionTitle>
            <span className="ml-auto text-[12px] text-text/55 tabular-nums">
              Portfolio {portfolioDone}/{portfolioTotal}{portfolioTotal > 0 ? ` · ${Math.round((portfolioDone / portfolioTotal) * 100)}%` : ''}
            </span>
          </div>
          {repoProgress.length === 0 ? (
            <p className="m-0 py-2 text-[13px] text-text/55">No roadmap counts yet. Progress appears after a roadmap scan.</p>
          ) : (
            <ul className="m-0 list-none p-0">
              {repoProgress.slice(0, 12).map(repo => (
                <li key={repo.repo} className="grid grid-cols-[minmax(0,190px)_minmax(0,1fr)_72px] items-center gap-3 py-[5px]">
                  <div className="flex min-w-0 flex-col">
                    <span className="truncate text-[13px]">{repo.repo}</span>
                    <span className="truncate text-[11px] text-text/55">{repo.phase}</span>
                  </div>
                  <div className="flex h-1.5 overflow-hidden rounded-xs bg-text/10" aria-hidden="true">
                    <div className="bg-accent-500" style={{ width: `${(repo.done / Math.max(1, repo.total)) * 100}%` }} />
                    <div className="bg-accent-800" style={{ width: `${(repo.active / Math.max(1, repo.total)) * 100}%` }} />
                  </div>
                  <span className="text-right text-[12px] tabular-nums">
                    {repo.done}/{repo.total}
                    <span className="text-text/55"> {repo.active ? `${repo.active} active` : 'idle'}</span>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>

      {selectedRow ? (
        <RunDrawer
          row={selectedRow}
          nowMs={nowMs}
          panelRef={drawerRef}
          onClose={closeDrawer}
          pendingActionId={pendingActionId}
          refusal={refusal}
          onAction={runAction}
          providerDetail={data.providers.find(p => p.provider === selectedRow.provider)?.detail ?? null}
        />
      ) : null}

      {stopDialogOpen ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-bg/70 p-4" onClick={closeStopDialog} data-testid="agent-ops-stop-dialog">
          <div
            ref={stopPanelRef}
            role="dialog"
            aria-modal="true"
            aria-labelledby="agent-ops-stop-title"
            className="mobile-sheet w-full max-w-[480px] rounded-[14px] bg-surface p-5 shadow-[0_0_0_1px_var(--color-status-crit),0_16px_40px_rgba(0,0,0,0.65)]"
            onClick={event => event.stopPropagation()}
          >
            <div className="flex items-center gap-2">
              <HandIcon className="w-[22px] h-[22px] text-status-crit-text" />
              <h2 id="agent-ops-stop-title" className="m-0 text-[16px] font-medium">Stop all agent work?</h2>
            </div>
            <div className="mt-3 flex flex-col gap-2 text-[14px]">
              <span>{describeStopSummary(victims)}</span>
              <span className="text-[13px] text-text/60">Runners are held, so nothing claims new work until you resume. Interrupted runs keep their branch and workspace. Nothing is pushed or merged.</span>
              {victims.some(v => v.provider === 'copilot') ? (
                <span className="text-[12px] text-text/60">Copilot runs cannot be killed from here: they are marked stopped, finish on GitHub, and are never merged by this stop.</span>
              ) : null}
            </div>
            <label className="mt-4 block text-[12px] text-text/60">
              Reason (recorded with the hold)
              <input
                type="text"
                value={stopReason}
                onChange={event => setStopReason(event.target.value)}
                placeholder="e.g. Bad prompt in the 4.0 batch"
                className="mt-1 w-full rounded-md border border-text/18 bg-bg px-2.5 py-1.5 text-[13px] text-text placeholder:text-text/40"
                data-testid="agent-ops-stop-reason"
              />
            </label>
            {stopError ? <p className="m-0 mt-2 text-[12px] text-status-crit-text" role="alert">{stopError}</p> : null}
            <div className="mt-4 flex justify-end gap-2">
              <button type="button" className={BUTTON_NEUTRAL} onClick={closeStopDialog} autoFocus disabled={stopBusy} title={stopBusy ? 'Stop request in flight' : 'Close without stopping anything'}>
                Keep running
              </button>
              <button
                type="button"
                className={BUTTON_DESTRUCTIVE}
                onClick={() => { void confirmStop(); }}
                disabled={stopBusy}
                title={stopBusy ? 'Stop request in flight' : 'Holds every runner and interrupts the runs in flight now'}
                data-testid="agent-ops-stop-confirm"
              >
                {stopBusy ? <SpinnerIcon className="w-4 h-4" /> : <HandIcon className="w-4 h-4" />}
                Stop {victims.length} run{victims.length === 1 ? '' : 's'} now
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
};

// ── Run drawer ─────────────────────────────────────────────────────────────

interface RunDrawerProps {
  row: AgentOpsRun;
  nowMs: number;
  panelRef: React.RefObject<HTMLDivElement | null>;
  onClose: () => void;
  pendingActionId: string | null;
  refusal: RefusalNote | null;
  onAction: (actionId: string, op: OperatorActionOp) => Promise<void>;
  providerDetail: string | null;
}

interface CheckRow {
  name: string;
  status: 'pass' | 'fail' | 'running' | 'none';
  label: string;
}

function checksFor(row: AgentOpsRun, readiness: MergeReadinessResult | null): CheckRow[] {
  const checks: CheckRow[] = [];
  const actions = row.run.actions;
  if (actions) {
    const status = String(actions.status ?? '').toLowerCase();
    const conclusion = String(actions.conclusion ?? '').toLowerCase();
    const name = actions.workflowName || 'GitHub Actions';
    if (status === 'completed' && conclusion === 'success') checks.push({ name, status: 'pass', label: 'passed' });
    else if (status === 'completed') checks.push({ name, status: 'fail', label: conclusion || 'failed' });
    else if (status) checks.push({ name, status: 'running', label: status.replace('_', ' ') });
  }
  if (readiness) {
    for (const blocker of readiness.blockers ?? []) {
      checks.push({ name: blocker.message, status: 'fail', label: blocker.code });
    }
    if (readiness.ready) checks.push({ name: 'Merge readiness', status: 'pass', label: 'ready' });
  }
  if (checks.length === 0) checks.push({ name: 'No checks reported yet', status: 'none', label: '' });
  return checks;
}

const CHECK_TONE: Record<CheckRow['status'], string> = {
  pass: 'text-accent-400',
  fail: 'text-status-crit-text',
  running: 'text-text/55',
  none: 'text-text/40',
};

const RunDrawer: React.FC<RunDrawerProps> = ({ row, nowMs, panelRef, onClose, pendingActionId, refusal, onAction, providerDetail }) => {
  const [events, setEvents] = useState<AgentRunEvent[] | null>(null);
  const [readiness, setReadiness] = useState<MergeReadinessResult | null>(null);
  const [detailError, setDetailError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    // Async fill: the list payload has no event log, and merge readiness is
    // one route per repository. Both are best-effort; the drawer already
    // shows everything the row knows.
    (async () => {
      try {
        const detail = await getAgentRunDetail(row.id);
        if (!cancelled) setEvents([...(detail.events ?? [])].sort((a, b) => (parseMs(b.timestamp) ?? 0) - (parseMs(a.timestamp) ?? 0)));
      } catch (error) {
        if (!cancelled) { setEvents([]); setDetailError(error instanceof Error ? error.message : String(error)); }
      }
      if (row.prNumber) {
        try {
          const result = await getMergeReadiness(row.repoId);
          if (!cancelled) setReadiness(result);
        } catch {
          if (!cancelled) setReadiness(null);
        }
      }
    })();
    return () => { cancelled = true; };
  }, [row.id, row.repoId, row.prNumber]);

  const buttons: Array<{ id: string; button: OperatorActionButton }> = [];
  if (row.state === 'READY_FOR_OPERATOR' && row.sha) {
    buttons.push({ id: `approve:${row.id}`, button: { label: `Approve ${row.sha.slice(0, 7)}`, consequence: true, op: { type: 'approve', runId: row.id, sha: row.sha } } });
  }
  if (row.state === 'OPERATOR_APPROVED') {
    buttons.push({ id: `merge:${row.id}`, button: { label: row.prNumber ? `Merge PR #${row.prNumber}` : 'Merge', consequence: true, op: { type: 'merge', repoId: row.repoId, runId: row.id } } });
  }
  if (row.state === 'CI_FAILED' || row.state === 'CI_PENDING' || row.state === 'PR_OPEN') {
    buttons.push({ id: `refresh:${row.id}`, button: { label: 'Re-evaluate run', consequence: true, op: { type: 'refresh', runId: row.id } } });
  }
  const terminal = ['COMPLETE', 'CANCELLED', 'MERGED', 'POST_MERGE_VERIFYING', 'MERGING'].includes(row.state);
  if (!terminal) {
    buttons.push({ id: `cancel:${row.id}`, button: { label: 'Cancel run', consequence: true, destructive: true, op: { type: 'cancel', repoName: row.repo, runId: row.id } } });
  }

  const facts: Array<[string, string]> = [
    ['Run', row.id],
    ['Branch', row.run.branch || '—'],
    ['Head SHA', row.sha || '—'],
    ['Attempt', String(row.attempt)],
    ['Diff', '— (not reported by the ledger)'],
    ['Value score', '—'],
  ];
  if (row.note) facts.push(['Note', row.note]);
  if (row.state === 'CAPACITY_WAIT' && providerDetail) facts.push(['Provider', providerDetail]);
  if (row.remote) facts.push(['Remote', 'Copilot keeps running on GitHub; this run will not be merged by the stop.']);

  const checks = checksFor(row, readiness);
  const offPath = row.index >= 0 && DELIVERY_STATES[row.index] !== row.state;

  return (
    <>
      <div className="fixed inset-0 z-40 bg-bg/60" onClick={onClose} data-testid="agent-ops-drawer-scrim" />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="agent-ops-drawer-title"
        className="mobile-sheet fixed inset-y-0 right-0 z-50 flex w-full max-w-[480px] flex-col overflow-y-auto bg-surface shadow-[0_16px_40px_rgba(0,0,0,0.65)] sm:rounded-l-[14px]"
        data-testid="agent-ops-drawer"
      >
        <div className="flex items-start gap-3 p-5">
          <div className="flex min-w-0 flex-1 flex-col gap-1">
            <span className="text-[10px] font-medium uppercase tracking-[0.08em] text-text/55">{row.repo} · {row.providerLabel}</span>
            <h2 id="agent-ops-drawer-title" className="m-0 text-[19px] font-medium leading-[1.25]">{row.title}</h2>
            <div className="mt-1 flex items-center gap-2">
              <StateTag row={row} className="text-[11px]" />
              <span className="text-[12px] text-text/55">{row.stage.label} · {formatAgo(row.updatedMs, nowMs)}</span>
            </div>
          </div>
          <button type="button" className={`${BUTTON_NEUTRAL} px-1.5`} onClick={onClose} aria-label="Close">
            <XIcon className="w-4 h-4" />
          </button>
        </div>

        <div className="flex flex-wrap gap-2 px-5 pb-4">
          {buttons.map(({ id, button }) => (
            <button
              key={id}
              type="button"
              className={buttonClass(button)}
              onClick={() => { void onAction(id, button.op); }}
              disabled={pendingActionId === id}
              title={pendingActionId === id ? 'Request in flight' : button.label}
            >
              {pendingActionId === id ? <SpinnerIcon className="w-3.5 h-3.5" /> : null}
              {button.label}
            </button>
          ))}
          {row.prUrl ? (
            <a href={row.prUrl} target="_blank" rel="noopener noreferrer" className={BUTTON_NEUTRAL}>
              <ArrowSquareOutIcon className="w-4 h-4" />
              PR #{row.prNumber ?? ''}
            </a>
          ) : null}
        </div>
        {refusal && buttons.some(b => b.id === refusal.actionId) ? (
          <p className="mx-5 mb-3 rounded-md border border-status-crit/45 bg-status-crit/10 px-2 py-1 text-[12px] text-status-crit-text" role="alert">{refusal.message}</p>
        ) : null}

        <dl className="m-0 grid grid-cols-[110px_minmax(0,1fr)] gap-x-3 gap-y-1.5 px-5 pb-4 text-[13px]">
          {facts.map(([label, value]) => (
            <React.Fragment key={label}>
              <dt className="text-text/55">{label}</dt>
              <dd className="m-0 break-all font-mono text-[12px]">{value}</dd>
            </React.Fragment>
          ))}
        </dl>

        <div className="flex flex-col gap-2 px-5 pb-4">
          <SectionTitle>CI checks</SectionTitle>
          <ul className="m-0 flex list-none flex-col gap-1 p-0">
            {checks.map((check, i) => (
              <li key={`${check.name}:${i}`} className="flex items-center gap-2 text-[13px]">
                <span className={`inline-block w-2 h-2 rounded-full ${check.status === 'pass' ? 'bg-accent-400' : check.status === 'fail' ? 'bg-status-crit' : check.status === 'running' ? 'bg-text/40 animate-pulse' : 'bg-text/20'}`} aria-hidden="true" />
                <span className={`min-w-0 flex-1 truncate ${CHECK_TONE[check.status]}`} title={check.name}>{check.name}</span>
                <span className="text-[12px] text-text/55">{check.label}</span>
              </li>
            ))}
          </ul>
        </div>

        <div className="flex flex-col gap-0.5 px-5 pb-4">
          <SectionTitle>Delivery state</SectionTitle>
          <ol className="m-0 mt-1 flex list-none flex-col gap-0.5 p-0" data-testid="agent-ops-drawer-states">
            {DELIVERY_STATES.map((state, i) => {
              const current = i === row.index;
              const done = i < row.index;
              return (
                <li key={state} className={`flex items-center gap-2 font-mono text-[11.5px] ${current ? 'text-text' : done ? 'text-text/60' : 'text-text/35'}`} aria-current={current ? 'step' : undefined}>
                  <span
                    className={`inline-block w-2 h-2 rounded-full ${done ? 'bg-accent-600' : current ? (row.tone === 'bad' ? 'bg-status-crit ring-[3px] ring-status-crit/30' : 'bg-accent-300 ring-[3px] ring-accent/30') : 'bg-text/15'}`}
                    aria-hidden="true"
                  />
                  {current && offPath ? `${state}  →  ${row.state}` : state}
                </li>
              );
            })}
          </ol>
        </div>

        <div className="flex flex-col gap-2 px-5 pb-8">
          <SectionTitle>Run log</SectionTitle>
          {events == null ? (
            <p className="m-0 text-[12.5px] text-text/55">Loading events…</p>
          ) : events.length === 0 ? (
            <p className="m-0 text-[12.5px] text-text/55">{detailError ? `Could not load the run log: ${detailError}` : 'No events recorded for this run.'}</p>
          ) : (
            <ol className="m-0 flex list-none flex-col gap-1 p-0">
              {events.map(event => (
                <li key={event.eventId} className="grid grid-cols-[70px_minmax(0,1fr)] gap-2 text-[12.5px]">
                  <span className="text-text/55">{formatAgo(parseMs(event.timestamp), nowMs)}</span>
                  <span>{event.summary}</span>
                </li>
              ))}
            </ol>
          )}
        </div>
      </div>
    </>
  );
};

export default AgentOpsView;
