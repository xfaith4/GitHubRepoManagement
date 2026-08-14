import React, { useState, useEffect } from 'react';
import {
  type ReleaseDispatchCheck,
  type ReleaseDispatchPacket,
  type DispatchExecuteResult,
  type RoadmapMaturityLevel,
  type RoadmapRepairPreview,
} from '../types';
import { checkRoadmapDispatch, executeRoadmapDispatch, applyRoadmapRepair, getRunnerPresence } from '../services/apiClient';
import { resolveRunnerPresence, resolveDispatchGate, runnerStartCommand, type RunnerPresencePayload } from '../lib/runnerPresence';
import { SpinnerIcon } from './icons';

const RUNNER_SEVERITY_CLASSES: Record<string, string> = {
  ok: 'border-emerald-700/50 bg-emerald-900/20 text-emerald-200',
  warning: 'border-amber-700/50 bg-amber-900/20 text-amber-100',
  error: 'border-red-700/60 bg-red-900/25 text-red-100',
  unknown: 'border-slate-700/60 bg-slate-800/40 text-slate-300',
};

interface RoadmapDispatchModalProps {
  isOpen: boolean;
  repoName: string | null;
  onClose: () => void;
  onDispatchComplete?: (result: DispatchExecuteResult) => void;
}

type DispatchPhase =
  | 'idle'
  | 'checking'
  | 'repair-needed'
  | 'repairing'
  | 'review-packet'
  | 'edit-prompt'
  | 'dispatching'
  | 'done'
  | 'error';

// ---------------------------------------------------------------------------
// Display helpers
// ---------------------------------------------------------------------------

const MATURITY_COLORS: Record<RoadmapMaturityLevel, string> = {
  'L0-Absent':              'bg-gray-800 text-gray-400 border-gray-600',
  'L1-Informal':            'bg-red-900/40 text-red-300 border-red-700/40',
  'L2-Structured':          'bg-orange-900/40 text-orange-300 border-orange-700/40',
  'L3-Contract-Ready':      'bg-yellow-900/40 text-yellow-300 border-yellow-700/40',
  'L4-Orchestration-Ready': 'bg-green-900/40 text-green-300 border-green-700/40',
};

function MaturityBadge({ level }: { level: RoadmapMaturityLevel }) {
  const cls = MATURITY_COLORS[level] ?? MATURITY_COLORS['L0-Absent'];
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded border text-xs font-medium ${cls}`}>
      {level}
    </span>
  );
}

function SectionHeader({ title }: { title: string }) {
  return (
    <div className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2 mt-4 first:mt-0">
      {title}
    </div>
  );
}

// ---------------------------------------------------------------------------
// DiffView — mirrored from RoadmapRepairModal.tsx
// ---------------------------------------------------------------------------

function DiffView({ current, proposed }: { current: string; proposed: string }) {
  const currentLines = current.split('\n');
  const proposedLines = proposed.split('\n');

  const renderLines = (lines: string[], highlight: boolean) => (
    <div className="font-mono text-xs leading-5 whitespace-pre-wrap text-gray-300">
      {lines.map((line, i) => {
        let cls = '';
        if (highlight) {
          if (line.startsWith('- [x]')) cls = 'bg-green-900/20 text-green-300';
          else if (line.startsWith('- [ ]')) cls = 'bg-blue-900/10 text-blue-200';
          else if (/^#{1,6} /.test(line)) cls = 'text-yellow-200 font-semibold';
        }
        return (
          <div key={i} className={`px-1 ${cls}`}>
            {line || '\u00A0'}
          </div>
        );
      })}
    </div>
  );

  return (
    <div className="grid grid-cols-2 gap-2 h-64 text-xs">
      <div className="flex flex-col">
        <div className="text-xs text-gray-500 font-medium mb-1 px-1">Current roadmap</div>
        <div className="flex-1 overflow-auto bg-gray-900/60 border border-gray-700/50 rounded p-2">
          {renderLines(currentLines, false)}
        </div>
      </div>
      <div className="flex flex-col">
        <div className="text-xs text-gray-500 font-medium mb-1 px-1">Proposed roadmap</div>
        <div className="flex-1 overflow-auto bg-gray-900/60 border border-green-800/30 rounded p-2">
          {renderLines(proposedLines, true)}
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main modal component
// ---------------------------------------------------------------------------

const RoadmapDispatchModal: React.FC<RoadmapDispatchModalProps> = ({
  isOpen,
  repoName,
  onClose,
  onDispatchComplete,
}) => {
  const [phase, setPhase] = useState<DispatchPhase>('idle');
  const [checkResult, setCheckResult] = useState<ReleaseDispatchCheck | null>(null);
  const [editedPrompt, setEditedPrompt] = useState('');
  const [dispatchResult, setDispatchResult] = useState<DispatchExecuteResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  // Release 3.0 — dispatch enqueues for the operator-session runner, so whether
  // one exists is the difference between "about to run" and "will sit forever".
  // Read it while the operator reviews the packet, not after they commit.
  const [runnerPresence, setRunnerPresence] = useState<RunnerPresencePayload | null>(null);
  const [runnerChecked, setRunnerChecked] = useState(false);

  // Run the dispatch readiness check whenever the modal opens
  useEffect(() => {
    if (!isOpen || !repoName) return;

    setPhase('checking');
    setCheckResult(null);
    setEditedPrompt('');
    setDispatchResult(null);
    setError(null);
    setRunnerPresence(null);
    setRunnerChecked(false);

    // getRunnerPresence resolves null on failure rather than throwing, so a
    // status hiccup cannot break the readiness check running alongside it.
    getRunnerPresence().then(presence => { setRunnerPresence(presence); setRunnerChecked(true); });

    checkRoadmapDispatch(repoName)
      .then(result => {
        setCheckResult(result);
        if (result.dispatchReady && result.releasePacket) {
          setEditedPrompt(result.releasePacket.generatedPrompt);
          setPhase('review-packet');
        } else {
          setPhase('repair-needed');
        }
      })
      .catch(err => {
        setError(err instanceof Error ? err.message : String(err));
        setPhase('error');
      });
  }, [isOpen, repoName]);

  const handleApplyAndContinue = async (repair: RoadmapRepairPreview) => {
    if (!repoName || !repair.proposedContent) return;
    setPhase('repairing');
    try {
      await applyRoadmapRepair(
        repoName,
        repair.previewId,
        repair.proposedContent,
        repair.roadmapPath ?? undefined,
        repair.originalMaturityLevel
      );
      // Re-check after repair
      setPhase('checking');
      setCheckResult(null);
      const result = await checkRoadmapDispatch(repoName);
      setCheckResult(result);
      if (result.dispatchReady && result.releasePacket) {
        setEditedPrompt(result.releasePacket.generatedPrompt);
        setPhase('review-packet');
      } else {
        setPhase('repair-needed');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setPhase('error');
    }
  };

  // Release 3.1 — acknowledgeNoRunner is the operator saying "queue it anyway,
  // I will start a runner". Without it the route refuses (409 runner-absent)
  // rather than writing an entry nothing can claim.
  const handleDispatch = async (options?: { acknowledgeNoRunner?: boolean }) => {
    if (!repoName || !editedPrompt) return;
    setPhase('dispatching');
    try {
      const result = await executeRoadmapDispatch(repoName, editedPrompt, {
        localPath: checkResult?.localPath ?? undefined,
        acknowledgeNoRunner: options?.acknowledgeNoRunner,
      });
      setDispatchResult(result);
      setPhase('done');
      onDispatchComplete?.(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setPhase('error');
    }
  };

  const handleRetry = () => {
    if (!repoName) return;
    setPhase('checking');
    setCheckResult(null);
    setEditedPrompt('');
    setDispatchResult(null);
    setError(null);

    checkRoadmapDispatch(repoName)
      .then(result => {
        setCheckResult(result);
        if (result.dispatchReady && result.releasePacket) {
          setEditedPrompt(result.releasePacket.generatedPrompt);
          setPhase('review-packet');
        } else {
          setPhase('repair-needed');
        }
      })
      .catch(err => {
        setError(err instanceof Error ? err.message : String(err));
        setPhase('error');
      });
  };

  if (!isOpen) return null;

  const repair = checkResult?.repairPreview ?? null;
  const packet: ReleaseDispatchPacket | null = checkResult?.releasePacket ?? null;
  // Prefer what the dispatch response reported over the pre-flight read: it is
  // the state at the moment the work was actually queued.
  const runnerView = resolveRunnerPresence(dispatchResult?.runner ?? runnerPresence);
  // The gate reads the PRE-FLIGHT presence only. Folding in dispatchResult would
  // evaluate the gate against the state after a dispatch that already happened.
  const dispatchGate = resolveDispatchGate(runnerPresence);

  return (
    <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-4">
      <div className="mobile-sheet bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-full max-w-3xl max-h-[90vh] flex flex-col">

        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-700 flex-shrink-0">
          <div>
            <h2 className="text-base font-semibold text-white">Dispatch Release to Copilot</h2>
            {repoName && (
              <p className="text-xs text-gray-400 mt-0.5">{repoName}</p>
            )}
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-white transition-colors text-lg leading-none"
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-5 py-4">

          {/* CHECKING */}
          {(phase === 'checking' || phase === 'idle') && (
            <div className="flex items-center gap-3 py-10 text-gray-400 justify-center">
              <SpinnerIcon className="w-5 h-5 animate-spin" />
              <span>Checking dispatch readiness…</span>
            </div>
          )}

          {/* REPAIRING */}
          {phase === 'repairing' && (
            <div className="flex items-center gap-3 py-10 text-gray-400 justify-center">
              <SpinnerIcon className="w-5 h-5 animate-spin" />
              <span>Applying roadmap repair…</span>
            </div>
          )}

          {/* DISPATCHING */}
          {phase === 'dispatching' && (
            <div className="flex items-center gap-3 py-10 text-gray-400 justify-center">
              <SpinnerIcon className="w-5 h-5 animate-spin" />
              <span>Dispatching to GitHub Copilot…</span>
            </div>
          )}

          {/* REPAIR NEEDED */}
          {phase === 'repair-needed' && checkResult && (
            <div className="space-y-4">
              {/* Maturity warning */}
              <div className="bg-orange-900/20 border border-orange-700/40 rounded-lg px-4 py-3">
                <div className="flex items-center gap-3 mb-1">
                  <span className="text-orange-400 font-semibold text-sm">Roadmap needs standardization</span>
                  <MaturityBadge level={checkResult.maturityLevel} />
                  <span className="text-gray-500 text-xs">(score {checkResult.maturityScore}/100)</span>
                </div>
                <p className="text-xs text-orange-300/80">
                  Dispatch requires L3-Contract-Ready or higher. Apply the repair below to standardize this roadmap, then dispatch.
                </p>
              </div>

              {repair && repair.previewState === 'repair-preview-ready' && repair.proposedContent ? (
                <>
                  <SectionHeader title="Proposed Repair" />
                  <DiffView
                    current={repair.currentContent ?? ''}
                    proposed={repair.proposedContent}
                  />
                  {repair.repairActions && repair.repairActions.length > 0 && (
                    <>
                      <SectionHeader title="Repair Actions" />
                      <div className="space-y-1.5">
                        {repair.repairActions.map((action, i) => (
                          <div
                            key={i}
                            className="rounded border px-3 py-2 text-sm bg-gray-800/50 border-gray-700/60"
                          >
                            <span className="text-xs font-medium text-gray-400 uppercase mr-2">
                              {action.severity}
                            </span>
                            <span className="text-gray-300">{action.description}</span>
                          </div>
                        ))}
                      </div>
                    </>
                  )}
                </>
              ) : repair?.previewState === 'repair-blocked' ? (
                <div className="bg-red-900/20 border border-red-700/40 rounded-lg px-4 py-3 text-sm text-red-300">
                  <div className="font-semibold mb-1">Repair blocked</div>
                  <div className="text-red-400/80">{repair.blockReason}</div>
                </div>
              ) : (
                <div className="text-sm text-gray-500 py-4 text-center">
                  No repair preview available for this roadmap.
                </div>
              )}
            </div>
          )}

          {/* REVIEW PACKET */}
          {phase === 'review-packet' && packet && (
            <div className="space-y-1">
              {/* Release 3.0 — dispatch enqueues for the operator-session
                  runner, so this warns BEFORE the operator spends the prompt
                  review. Queueing into an empty room otherwise looks identical
                  to queueing into a running one until nothing ever happens. */}
              {runnerChecked && runnerView.warnBeforeQueueing && (
                <div
                  data-testid="dispatch-runner-warning"
                  role={runnerView.needsAttention ? 'alert' : 'status'}
                  className={`mb-2 rounded-lg border px-3 py-2 text-xs ${RUNNER_SEVERITY_CLASSES[runnerView.severity]}`}
                >
                  <span className="font-semibold">{runnerView.label}.</span>{' '}
                  <span>{runnerView.detail}</span>
                </div>
              )}

              {/* Release header */}
              <div className="bg-indigo-900/20 border border-indigo-700/40 rounded-lg p-4 mb-2">
                <div className="text-base font-semibold text-indigo-200 mb-1">{packet.releaseName}</div>
                {packet.releaseGoal && (
                  <p className="text-sm text-indigo-300/80">{packet.releaseGoal}</p>
                )}
                <div className="flex items-center gap-2 mt-2">
                  <MaturityBadge level={packet.maturityLevel} />
                  <span className="text-xs text-gray-500">score {packet.maturityScore}/100</span>
                </div>
              </div>

              {/* Pending milestones */}
              <SectionHeader title={`Engineering Milestones (${packet.pendingMilestones.length} pending)`} />
              <div className="bg-gray-800/40 border border-gray-700/60 rounded-lg p-3">
                <ol className="space-y-1.5 list-none">
                  {packet.pendingMilestones.map((m, i) => (
                    <li key={i} className="flex items-start gap-2 text-sm text-gray-300">
                      <span className="text-blue-400 flex-shrink-0 font-mono text-xs mt-0.5">{i + 1}.</span>
                      <span>{m}</span>
                    </li>
                  ))}
                </ol>
              </div>

              {/* Acceptance criteria */}
              {packet.acceptanceCriteria.length > 0 && (
                <>
                  <SectionHeader title="Acceptance Criteria" />
                  <div className="bg-gray-800/40 border border-gray-700/60 rounded-lg p-3">
                    <ul className="space-y-1">
                      {packet.acceptanceCriteria.map((c, i) => (
                        <li key={i} className="flex items-start gap-2 text-sm text-gray-300">
                          <span className="text-green-500 flex-shrink-0 mt-0.5">✓</span>
                          <span>{c}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                </>
              )}

              {/* Out of scope / guardrails */}
              {packet.outOfScope.length > 0 && (
                <>
                  <SectionHeader title="Guardrails (Out of Scope)" />
                  <div className="bg-gray-800/40 border border-gray-700/60 rounded-lg p-3">
                    <ul className="space-y-1">
                      {packet.outOfScope.map((o, i) => (
                        <li key={i} className="flex items-start gap-2 text-sm text-gray-300">
                          <span className="text-yellow-500 flex-shrink-0 mt-0.5">⚠</span>
                          <span>{o}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                </>
              )}
            </div>
          )}

          {/* EDIT PROMPT */}
          {phase === 'edit-prompt' && (
            <div>
              <p className="text-sm text-gray-400 mb-3">
                Review and edit the generated Copilot task prompt before dispatching.
              </p>
              <textarea
                value={editedPrompt}
                onChange={e => setEditedPrompt(e.target.value)}
                rows={22}
                className="w-full bg-gray-800 border border-gray-700 rounded-lg p-3 text-xs text-gray-200 font-mono leading-relaxed resize-y focus:outline-none focus:border-indigo-600"
                spellCheck={false}
              />
            </div>
          )}

          {/* DONE */}
          {phase === 'done' && dispatchResult && (
            <div className="space-y-3">
              {/* Release 3.0: the host enqueues, it does not start. Saying
                  "dispatched successfully" when no runner exists would be a
                  green tick over work that will never move. */}
              <div
                data-testid="dispatch-outcome"
                className={`rounded-lg border p-4 flex items-start gap-3 ${
                  runnerView.warnBeforeQueueing
                    ? 'bg-amber-900/20 border-amber-700/40'
                    : 'bg-green-900/20 border-green-700/40'
                }`}
              >
                <span className={`text-xl flex-shrink-0 ${runnerView.warnBeforeQueueing ? 'text-amber-400' : 'text-green-400'}`}>
                  {runnerView.warnBeforeQueueing ? '!' : '✓'}
                </span>
                <div>
                  <div className={`font-semibold text-sm mb-0.5 ${runnerView.warnBeforeQueueing ? 'text-amber-200' : 'text-green-300'}`}>
                    {runnerView.warnBeforeQueueing
                      ? 'Queued — but nothing is running to pick it up'
                      : 'Queued for the operator runner'}
                  </div>
                  <div className={`text-xs ${runnerView.warnBeforeQueueing ? 'text-amber-300/80' : 'text-green-400/70'}`}>
                    {dispatchResult.message}
                  </div>
                </div>
              </div>
              <div className="bg-gray-800/60 border border-gray-700 rounded-lg p-3 space-y-1.5 text-sm">
                <div className="flex gap-2">
                  <span className="text-gray-400 w-24 flex-shrink-0">Run ID</span>
                  <span className="text-gray-300 font-mono text-xs">{dispatchResult.runId || '—'}</span>
                </div>
                <div className="flex gap-2">
                  <span className="text-gray-400 w-24 flex-shrink-0">Repository</span>
                  <span className="text-gray-300 font-mono text-xs">{dispatchResult.githubRepo}</span>
                </div>
                <div className="flex gap-2">
                  <span className="text-gray-400 w-24 flex-shrink-0">Status</span>
                  <span className="text-green-300 font-medium">{dispatchResult.status}</span>
                </div>
                <div className="flex gap-2">
                  <span className="text-gray-400 w-24 flex-shrink-0">Started at</span>
                  <span className="text-gray-400 text-xs">{new Date(dispatchResult.startedAt).toLocaleString()}</span>
                </div>
              </div>
              <p className="text-xs text-gray-500">
                The portal cannot start a GitHub agent task itself —{' '}
                <code className="text-gray-400">gh agent-task</code> needs an OAuth credential the
                service cannot hold. The task runner picks this up in your own session and creates
                it there; GitHub Copilot then branches, implements the milestones, and opens a PR
                for your review.
              </p>
              {runnerView.warnBeforeQueueing && (
                <p className="text-xs text-amber-300/80">
                  Start the runner to release this task:{' '}
                  <code className="rounded bg-gray-800 px-1 py-0.5">{runnerStartCommand()}</code>
                </p>
              )}
            </div>
          )}

          {/* ERROR */}
          {phase === 'error' && (
            <div className="space-y-3">
              <div className="bg-red-900/30 border border-red-700/40 rounded-lg px-4 py-3 text-sm text-red-300">
                <div className="font-semibold mb-1">Dispatch failed</div>
                <div className="text-red-400/80 text-xs whitespace-pre-wrap">{error}</div>
              </div>
            </div>
          )}

        </div>

        {/* Footer */}
        <div className="px-5 py-3 border-t border-gray-700 flex items-center justify-between gap-2 flex-shrink-0">
          <div>
            {phase === 'edit-prompt' && (
              <button
                onClick={() => setPhase('review-packet')}
                className="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-300 rounded border border-gray-600 transition-colors"
              >
                ← Back
              </button>
            )}
          </div>
          <div className="flex items-center gap-2">
            {/* REPAIR NEEDED — Apply & Continue */}
            {phase === 'repair-needed' && repair && repair.previewState === 'repair-preview-ready' && repair.proposedContent && (
              <button
                onClick={() => handleApplyAndContinue(repair)}
                className="px-4 py-1.5 text-sm bg-orange-700 hover:bg-orange-600 text-white rounded border border-orange-600 transition-colors font-medium"
              >
                Apply Repair &amp; Continue
              </button>
            )}
            {/* REVIEW PACKET — Review Prompt */}
            {phase === 'review-packet' && (
              <button
                onClick={() => setPhase('edit-prompt')}
                className="px-4 py-1.5 text-sm bg-indigo-700 hover:bg-indigo-600 text-white rounded border border-indigo-600 transition-colors font-medium"
              >
                Review Prompt →
              </button>
            )}
            {/* EDIT PROMPT — Dispatch to Copilot.
                Release 3.1: this is the control that used to be enabled into an
                empty room. It now renders disabled with the unmet precondition
                named beside it, and the deliberate override sits next to it so
                capability is explained rather than removed. */}
            {phase === 'edit-prompt' && (
              <>
                {!dispatchGate.canQueue && (
                  <span
                    data-testid="dispatch-precondition"
                    className="text-xs text-amber-300/90 max-w-md text-right"
                  >
                    {dispatchGate.unmetPrecondition}
                  </span>
                )}
                {!dispatchGate.canQueue && (
                  <button
                    onClick={() => handleDispatch({ acknowledgeNoRunner: true })}
                    disabled={!editedPrompt.trim()}
                    title={!editedPrompt.trim() ? 'The dispatch prompt is empty; there is nothing to queue.' : dispatchGate.unmetPrecondition ?? 'Queue this work anyway.'}
                    data-testid="dispatch-override"
                    className="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 disabled:opacity-40 disabled:cursor-not-allowed text-amber-200 rounded border border-amber-700/50 transition-colors"
                  >
                    {dispatchGate.overrideLabel}
                  </button>
                )}
                <button
                  onClick={() => handleDispatch()}
                  disabled={!editedPrompt.trim() || !dispatchGate.canQueue}
                  data-testid="dispatch-submit"
                  title={dispatchGate.canQueue ? undefined : dispatchGate.unmetPrecondition}
                  className="px-4 py-1.5 text-sm bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 disabled:cursor-not-allowed text-white rounded border border-indigo-500 transition-colors font-medium"
                >
                  Dispatch to Copilot
                </button>
              </>
            )}
            {/* ERROR — Retry */}
            {phase === 'error' && (
              <button
                onClick={handleRetry}
                className="px-4 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded border border-gray-600 transition-colors"
              >
                Retry
              </button>
            )}
            <button
              onClick={onClose}
              className="px-4 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded border border-gray-600 transition-colors"
            >
              {phase === 'done' ? 'Close' : 'Cancel'}
            </button>
          </div>
        </div>

      </div>
    </div>
  );
};

export default RoadmapDispatchModal;
