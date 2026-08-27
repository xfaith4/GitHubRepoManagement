import React, { useCallback, useState } from 'react';
import {
  type FoundationDomainRecord,
  type FoundationNextAction,
  type RepositoryConclusion,
  describeConclusion,
  describeDomainStatus,
  explainUnrunnableAction,
  isRunnableNextAction,
} from '../lib/foundationConclusion';

// Release 3.6 milestone 2 — the outcome card.
//
// One repository, one explainable conclusion: what the product concluded, why,
// each foundation domain's status with its evidence, and — where improvement is
// warranted — one next action the console can actually run, preview-first.
//
// Two rules this component exists to keep:
//   1. No repository reads as `L0-Absent` or "not applicable" and nothing else.
//      A repo without a roadmap gets a conclusion and a reason like any other.
//   2. `appropriate as-is` is a first-class outcome, rendered with the same
//      structure as `strengthen` — not an empty state, not a shrug.

const TONE_BADGE: Record<'attention' | 'healthy' | 'unknown', string> = {
  attention: 'bg-amber-900/40 border-amber-600 text-amber-200',
  healthy: 'bg-emerald-900/30 border-emerald-600 text-emerald-200',
  unknown: 'bg-slate-800 border-slate-600 text-slate-300',
};

const STATUS_DOT: Record<string, string> = {
  present: 'bg-emerald-400',
  weak: 'bg-amber-400',
  missing: 'bg-red-400',
  'not-applicable': 'bg-slate-600',
  'not-scored': 'bg-sky-500',
};

const STATUS_TEXT: Record<string, string> = {
  present: 'text-emerald-300',
  weak: 'text-amber-300',
  missing: 'text-red-300',
  'not-applicable': 'text-slate-400',
  'not-scored': 'text-sky-300',
};

function DomainRow({ domain }: { domain: FoundationDomainRecord }) {
  const status = describeDomainStatus(domain.status);
  return (
    <li className="py-2 border-b border-gray-700/60 last:border-b-0">
      <div className="flex items-center gap-2">
        <span
          className={`inline-block w-2 h-2 rounded-full flex-shrink-0 ${STATUS_DOT[domain.status] ?? 'bg-slate-600'}`}
          aria-hidden="true"
        />
        <span className="text-sm text-gray-200 font-medium">{domain.title}</span>
        <span className={`text-xs ${STATUS_TEXT[domain.status] ?? 'text-slate-400'}`}>{status.label}</span>
      </div>
      {domain.evidence.length > 0 && (
        <ul className="mt-1 ml-4 space-y-0.5">
          {domain.evidence.map((line, i) => (
            <li key={i} className="text-xs text-gray-400 leading-relaxed">
              {line}
            </li>
          ))}
        </ul>
      )}
    </li>
  );
}

export interface OutcomeCardProps {
  conclusion: RepositoryConclusion;
  /** Runs the preview-first next action. Omit to render the action as a label only. */
  onRunNextAction?: (action: FoundationNextAction) => Promise<void> | void;
  /** Shown when the backend reported the conclusion contract broken for this repo. */
  contractViolations?: string[];
}

export const OutcomeCard: React.FC<OutcomeCardProps> = ({ conclusion, onRunNextAction, contractViolations }) => {
  const [running, setRunning] = useState(false);
  const [actionError, setActionError] = useState('');
  const presentation = describeConclusion(conclusion.conclusion);
  const action = conclusion.nextAction;
  const runnable = isRunnableNextAction(action) && Boolean(onRunNextAction);
  const unrunnableReason = explainUnrunnableAction(action);

  const handleRun = useCallback(async () => {
    if (!action || !onRunNextAction) return;
    setRunning(true);
    setActionError('');
    try {
      await onRunNextAction(action);
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'The next action could not be started.');
    } finally {
      setRunning(false);
    }
  }, [action, onRunNextAction]);

  return (
    <section
      className="bg-gray-900/60 border border-gray-700 rounded-lg p-4 space-y-3"
      aria-label={`Outcome for ${conclusion.repoName || 'this repository'}`}
    >
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div className="flex items-center gap-2 flex-wrap">
          <span className={`text-xs font-semibold px-2.5 py-1 rounded border ${TONE_BADGE[presentation.tone]}`}>
            {presentation.label}
          </span>
          {conclusion.kind && conclusion.kind !== 'unknown' && (
            <span className="text-[11px] text-gray-400 bg-gray-800 border border-gray-700 rounded px-2 py-0.5">
              {conclusion.kind}
            </span>
          )}
        </div>
        <span className="text-[11px] text-gray-500" title={conclusion.kindBasis}>
          {conclusion.maturityLevel}
        </span>
      </div>

      {/* The why. Always present: the backend refuses to emit a conclusion without one. */}
      <p className="text-sm text-gray-200 leading-relaxed">{conclusion.reason}</p>

      {contractViolations && contractViolations.length > 0 && (
        <div className="bg-red-950/60 border border-red-700 rounded px-3 py-2 space-y-1">
          <p className="text-xs text-red-300 font-medium">
            This conclusion did not satisfy the product&apos;s own contract:
          </p>
          <ul className="space-y-0.5">
            {contractViolations.map((v, i) => (
              <li key={i} className="text-xs text-red-300/90">
                {v}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div>
        <h4 className="text-[11px] font-semibold text-gray-400 uppercase tracking-wide mb-1">Foundations</h4>
        <ul className="divide-y-0">
          {conclusion.domains.map(domain => (
            <DomainRow key={domain.domain} domain={domain} />
          ))}
        </ul>
      </div>

      {action && (
        <div className="pt-1 space-y-2">
          <h4 className="text-[11px] font-semibold text-gray-400 uppercase tracking-wide">Next action</h4>
          <div className="flex items-center gap-3 flex-wrap">
            <button
              type="button"
              onClick={handleRun}
              disabled={!runnable || running}
              title={
                unrunnableReason ??
                (onRunNextAction
                  ? `${action.method} ${action.route} — previews the change first; nothing is applied.`
                  : 'Preview-first: nothing is applied.')
              }
              className="px-3 py-2 bg-indigo-600 hover:bg-indigo-500 disabled:bg-gray-700 disabled:text-gray-500 text-white text-sm rounded-lg font-medium transition-colors"
            >
              {running ? 'Starting…' : action.label}
            </button>
            {action.previewFirst && (
              <span className="text-[11px] text-gray-500">Preview first — nothing is applied.</span>
            )}
          </div>
          {unrunnableReason && <p className="text-xs text-amber-300/90">{unrunnableReason}</p>}
          {actionError && <p className="text-xs text-red-300">{actionError}</p>}
        </div>
      )}

      {!action && conclusion.conclusion === 'appropriate-as-is' && (
        <p className="text-xs text-gray-500">
          No action is warranted. This is an outcome, not an absence of one.
        </p>
      )}
    </section>
  );
};

export default OutcomeCard;
