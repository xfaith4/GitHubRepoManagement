import React, { useState, useEffect } from 'react';
import { type CopilotTaskPacket, type CopilotTaskHistoryItem } from '../types';
import { previewCopilotTaskPacket, getCopilotTaskHistory } from '../services/apiClient';
import { SpinnerIcon } from './icons';

interface CopilotTaskPreviewModalProps {
  isOpen: boolean;
  repoName: string | null;
  roadmapPath?: string;
  onClose: () => void;
  /**
   * Lane 0.17 — when provided, the modal offers "Dispatch to Lane" after a
   * successful preview, so the preview → dispatch flow no longer dead-ends
   * at Copy/Close. The callback returns the backend's verdict; a refusal
   * (both lanes occupied, repo not dispatchable) renders inline.
   */
  onDispatch?: (repoName: string) => Promise<{ success: boolean; error?: string | null }>;
}

/**
 * Returns true when the history item's repoName matches the current repo filter.
 * Handles both bare repo names (e.g. "MyRepo") and GitHub "owner/repo" paths
 * that the task scripts may record (e.g. "owner/MyRepo").
 */
function matchesRepoName(itemRepoName: string, filterRepoName: string | null): boolean {
  if (!filterRepoName) return true;
  return itemRepoName === filterRepoName || itemRepoName.endsWith('/' + filterRepoName);
}

const SEVERITY_COLORS: Record<string, string> = {  critical: 'text-red-400',
  warning: 'text-yellow-400',
  info: 'text-blue-400',
};

const SEVERITY_BG: Record<string, string> = {
  critical: 'bg-red-900/30 border-red-700/40',
  warning: 'bg-yellow-900/30 border-yellow-700/40',
  info: 'bg-blue-900/20 border-blue-700/30',
};

const STATUS_COLORS: Record<string, string> = {
  preview: 'text-blue-400',
  started: 'text-green-400',
  success: 'text-green-400',
  failed: 'text-red-400',
};

const VALUE_TIER_LABELS: Record<string, string> = {
  highest: 'Highest',
  high: 'High',
  medium: 'Medium',
  low: 'Low',
  deferred: 'Deferred',
  unscored: 'Unscored',
};

const VALUE_TIER_BADGES: Record<string, string> = {
  highest: 'bg-emerald-900/40 border-emerald-700/50 text-emerald-300',
  high: 'bg-green-900/40 border-green-700/50 text-green-300',
  medium: 'bg-yellow-900/40 border-yellow-700/50 text-yellow-300',
  low: 'bg-slate-800 border-slate-700 text-slate-300',
  deferred: 'bg-gray-800 border-gray-700 text-gray-400',
  unscored: 'bg-gray-800 border-gray-700 text-gray-400',
};

const CONSTRAINT_SOURCE_LABELS: Record<string, string> = {
  'roadmap-out-of-scope': 'Out of Scope',
  'portfolio-blocker': 'Portfolio',
  'docs-critical': 'Docs',
};

function SectionHeader({ title }: { title: string }) {
  return (
    <div className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2 mt-4 first:mt-0">
      {title}
    </div>
  );
}

const CopilotTaskPreviewModal: React.FC<CopilotTaskPreviewModalProps> = ({
  isOpen,
  repoName,
  roadmapPath,
  onClose,
  onDispatch,
}) => {
  const [activeTab, setActiveTab] = useState<'packet' | 'prompt' | 'history'>('packet');
  const [packet, setPacket] = useState<CopilotTaskPacket | null>(null);
  const [history, setHistory] = useState<CopilotTaskHistoryItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [dispatching, setDispatching] = useState(false);
  const [dispatched, setDispatched] = useState(false);
  const [dispatchError, setDispatchError] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen || !repoName) return;
    setPacket(null);
    setError(null);
    setActiveTab('packet');
    setDispatched(false);
    setDispatchError(null);
    setLoading(true);

    previewCopilotTaskPacket(repoName, roadmapPath)
      .then(p => setPacket(p))
      .catch(err => setError(err instanceof Error ? err.message : String(err)))
      .finally(() => setLoading(false));
  }, [isOpen, repoName, roadmapPath]);

  useEffect(() => {
    if (!isOpen || activeTab !== 'history') return;
    setHistoryLoading(true);
    getCopilotTaskHistory(20)
      .then(items => setHistory(items.filter(i => matchesRepoName(i.repoName, repoName))))
      .catch(() => setHistory([]))
      .finally(() => setHistoryLoading(false));
  }, [isOpen, activeTab, repoName]);

  const handleCopyPrompt = async () => {
    if (!packet) return;
    try {
      await navigator.clipboard.writeText(packet.generatedPrompt);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // clipboard may not be available in all contexts
    }
  };

  const handleDispatch = async () => {
    if (!onDispatch || !repoName || dispatching || dispatched) return;
    setDispatching(true);
    setDispatchError(null);
    try {
      const result = await onDispatch(repoName);
      if (result.success) {
        setDispatched(true);
      } else {
        setDispatchError(result.error ?? 'Dispatch failed.');
      }
    } catch (err) {
      setDispatchError(err instanceof Error ? err.message : String(err));
    } finally {
      setDispatching(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-4">
      <div className="mobile-sheet bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-full max-w-3xl max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-700 flex-shrink-0">
          <div>
            <h2 className="text-base font-semibold text-white">
              Preview Copilot Task
            </h2>
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

        {/* Tabs */}
        <div className="flex border-b border-gray-700 px-5 flex-shrink-0">
          {(['packet', 'prompt', 'history'] as const).map(tab => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors capitalize ${
                activeTab === tab
                  ? 'border-indigo-500 text-indigo-300'
                  : 'border-transparent text-gray-400 hover:text-gray-200'
              }`}
            >
              {tab === 'packet' ? 'Task Packet' : tab === 'prompt' ? 'Generated Prompt' : 'History'}
            </button>
          ))}
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-5 py-4">
          {/* Loading */}
          {loading && (
            <div className="flex items-center gap-3 py-8 text-gray-400 justify-center">
              <SpinnerIcon className="w-5 h-5 animate-spin" />
              <span>Building task packet…</span>
            </div>
          )}

          {/* Error — Lane 0.17: the remedy hint must match the failure. The
              roadmap-scan hint used to render on EVERY error, including a
              network failure it could not fix. */}
          {!loading && error && (
            <div className="bg-red-900/30 border border-red-700/40 rounded-lg px-4 py-3 text-sm text-red-300">
              <div className="font-semibold mb-1">Failed to build task packet</div>
              <div className="text-red-400/80">{error}</div>
              <div className="mt-2 text-xs text-red-400/60">
                {/roadmap/i.test(error)
                  ? 'Ensure a roadmap scan has been run (Doc Readiness Queue → Rescan roadmaps) and this repository has pending roadmap items.'
                  : 'The API host did not return a usable response — check that the portal is reachable, then retry.'}
              </div>
            </div>
          )}

          {/* Packet tab */}
          {!loading && !error && packet && activeTab === 'packet' && (
            <div className="space-y-1">
              {/* Repo context */}
              <SectionHeader title="Repository Context" />
              <div className="bg-gray-800/60 border border-gray-700 rounded-lg p-3 space-y-1.5 text-sm">
                <div className="flex gap-2">
                  <span className="text-gray-400 w-28 flex-shrink-0">Repository</span>
                  <span className="text-white font-mono">{packet.repoContext.repoName}</span>
                </div>
                {packet.repoContext.repoPath && (
                  <div className="flex gap-2">
                    <span className="text-gray-400 w-28 flex-shrink-0">Local path</span>
                    <span className="text-gray-300 font-mono text-xs truncate" title={packet.repoContext.repoPath}>{packet.repoContext.repoPath}</span>
                  </div>
                )}
                <div className="flex gap-2">
                  <span className="text-gray-400 w-28 flex-shrink-0">Roadmap file</span>
                  <span className="text-gray-300 font-mono text-xs truncate" title={packet.repoContext.roadmapPath}>{packet.repoContext.roadmapPath}</span>
                </div>
                {packet.repoContext.dispatchReadiness && (
                  <div className="flex gap-2">
                    <span className="text-gray-400 w-28 flex-shrink-0">Readiness</span>
                    <span className="text-green-300 font-medium">{packet.repoContext.dispatchReadiness}</span>
                  </div>
                )}
                {packet.repoContext.lifecycleState && (
                  <div className="flex gap-2">
                    <span className="text-gray-400 w-28 flex-shrink-0">Lifecycle</span>
                    <span className="text-gray-200">{packet.repoContext.lifecycleState}</span>
                  </div>
                )}
                {packet.repoContext.maturityLevel && (
                  <div className="flex gap-2">
                    <span className="text-gray-400 w-28 flex-shrink-0">Maturity</span>
                    <span className="text-gray-200">
                      {packet.repoContext.maturityLevel}
                      {typeof packet.repoContext.maturityScore === 'number' ? ` (${packet.repoContext.maturityScore}/100)` : ''}
                    </span>
                  </div>
                )}
                {packet.repoContext.recommendedAction && (
                  <div className="flex gap-2">
                    <span className="text-gray-400 w-28 flex-shrink-0">Next action</span>
                    <span className="text-gray-300">{packet.repoContext.recommendedAction}</span>
                  </div>
                )}
                {packet.repoContext.dispatchReadinessExplanation && (
                  <div className="flex gap-2">
                    <span className="text-gray-400 w-28 flex-shrink-0">Why ready</span>
                    <span className="text-gray-300">{packet.repoContext.dispatchReadinessExplanation}</span>
                  </div>
                )}
                {(typeof packet.repoContext.readmeScore === 'number' ||
                  typeof packet.repoContext.roadmapScore === 'number' ||
                  typeof packet.repoContext.documentationHealthScore === 'number') && (
                  <div className="flex gap-2">
                    <span className="text-gray-400 w-28 flex-shrink-0">Scores</span>
                    <span className="text-gray-300">
                      README {packet.repoContext.readmeScore ?? 'n/a'} · ROADMAP {packet.repoContext.roadmapScore ?? 'n/a'} · Docs {packet.repoContext.documentationHealthScore ?? 'n/a'}
                    </span>
                  </div>
                )}
                <div className="flex gap-2">
                  <span className="text-gray-400 w-28 flex-shrink-0">Packet ID</span>
                  <span className="text-gray-500 font-mono text-xs">{packet.runId}</span>
                </div>
              </div>

              {(packet.readmeContext.summary || packet.readmeContext.headings.length > 0) && (
                <>
                  <SectionHeader title="README Context" />
                  <div className="bg-gray-800/40 border border-gray-700/60 rounded-lg p-3 space-y-2">
                    {packet.readmeContext.summary && (
                      <p className="text-sm text-gray-300 leading-relaxed">{packet.readmeContext.summary}</p>
                    )}
                    {packet.readmeContext.headings.length > 0 && (
                      <div className="flex flex-wrap gap-1.5">
                        {packet.readmeContext.headings.map(heading => (
                          <span
                            key={heading}
                            className="px-2 py-0.5 rounded border border-gray-700 bg-gray-900/70 text-xs text-gray-300"
                          >
                            {heading}
                          </span>
                        ))}
                      </div>
                    )}
                    <div className="flex flex-wrap gap-2 text-xs">
                      <span className={`px-2 py-0.5 rounded border ${packet.readmeContext.hasSetupGuidance ? 'border-green-700/50 bg-green-900/30 text-green-300' : 'border-gray-700 bg-gray-900/60 text-gray-500'}`}>
                        Setup guidance
                      </span>
                      <span className={`px-2 py-0.5 rounded border ${packet.readmeContext.hasUsageGuidance ? 'border-green-700/50 bg-green-900/30 text-green-300' : 'border-gray-700 bg-gray-900/60 text-gray-500'}`}>
                        Usage guidance
                      </span>
                      <span className={`px-2 py-0.5 rounded border ${packet.readmeContext.hasArchitectureGuidance ? 'border-green-700/50 bg-green-900/30 text-green-300' : 'border-gray-700 bg-gray-900/60 text-gray-500'}`}>
                        Architecture context
                      </span>
                    </div>
                  </div>
                </>
              )}

              {(packet.roadmapContext.releaseName || packet.roadmapContext.pendingMilestones.length > 0) && (
                <>
                  <SectionHeader title="Release Context" />
                  <div className="bg-gray-800/40 border border-gray-700/60 rounded-lg p-3 space-y-2">
                    {packet.roadmapContext.releaseName && (
                      <div className="text-sm text-white font-medium">{packet.roadmapContext.releaseName}</div>
                    )}
                    {packet.roadmapContext.releaseGoal && (
                      <p className="text-sm text-gray-300">{packet.roadmapContext.releaseGoal}</p>
                    )}
                    {packet.roadmapContext.pendingMilestones.length > 0 && (
                      <div>
                        <div className="text-xs text-gray-500 uppercase tracking-wide mb-1">Release milestones</div>
                        <div className="space-y-1">
                          {packet.roadmapContext.pendingMilestones.slice(0, 5).map(item => (
                            <div key={item} className="text-sm text-gray-300">- {item}</div>
                          ))}
                        </div>
                      </div>
                    )}
                    {packet.roadmapContext.outOfScope.length > 0 && (
                      <div>
                        <div className="text-xs text-gray-500 uppercase tracking-wide mb-1">Out of scope</div>
                        <div className="space-y-1">
                          {packet.roadmapContext.outOfScope.map(item => (
                            <div key={item} className="text-sm text-gray-400">- {item}</div>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                </>
              )}

              {/* Selected roadmap item */}
              <SectionHeader title="Selected Roadmap Item" />
              <div className="bg-indigo-900/20 border border-indigo-700/40 rounded-lg p-3 space-y-2">
                <div className="flex items-center gap-2 flex-wrap">
                  <div className="text-white font-medium text-sm">{packet.selectedRoadmapItem.text}</div>
                  {packet.selectedRoadmapItem.selectionSource && (
                    <span className="px-2 py-0.5 rounded border border-indigo-700/50 bg-indigo-950/50 text-[11px] text-indigo-300 uppercase tracking-wide">
                      {packet.selectedRoadmapItem.selectionSource === 'value-ranked' ? 'Value-ranked' : 'Roadmap-order'}
                    </span>
                  )}
                </div>
                <div className="text-xs text-indigo-400/80">Section: {packet.selectedRoadmapItem.section}</div>
                {(packet.selectedRoadmapItem.tags?.length ?? 0) > 0 && (
                  <div className="flex flex-wrap gap-1.5">
                    {packet.selectedRoadmapItem.tags?.map(tag => (
                      <span key={tag} className="px-2 py-0.5 rounded border border-indigo-700/30 bg-indigo-900/20 text-[11px] text-indigo-200">
                        [{tag}]
                      </span>
                    ))}
                  </div>
                )}
                {packet.selectedRoadmapItem.previousItem && (
                  <div className="text-xs text-gray-500">
                    ← Previous item: <span className="text-gray-400">{packet.selectedRoadmapItem.previousItem}</span>
                  </div>
                )}
                {packet.selectedRoadmapItem.nextItem && (
                  <div className="text-xs text-gray-500">
                    → Next item: <span className="text-gray-400">{packet.selectedRoadmapItem.nextItem}</span>
                  </div>
                )}
              </div>

              {(typeof packet.valueContext.valueScore === 'number' ||
                packet.valueContext.rationale.length > 0 ||
                packet.valueContext.topValueItemText) && (
                <>
                  <SectionHeader title="Value Context" />
                  <div className="bg-emerald-900/10 border border-emerald-700/30 rounded-lg p-3 space-y-2">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-sm text-gray-300">Selected by {packet.valueContext.selectedBy === 'value-ranked' ? 'value ranking' : 'roadmap order'}</span>
                      {typeof packet.valueContext.valueScore === 'number' && (
                        <span className="px-2.5 py-0.5 rounded border border-emerald-700/40 bg-emerald-900/30 text-sm text-emerald-300 font-semibold">
                          {packet.valueContext.valueScore}
                        </span>
                      )}
                      {packet.valueContext.valueTier && (
                        <span className={`px-2 py-0.5 rounded border text-xs ${VALUE_TIER_BADGES[packet.valueContext.valueTier] ?? VALUE_TIER_BADGES.unscored}`}>
                          {VALUE_TIER_LABELS[packet.valueContext.valueTier] ?? packet.valueContext.valueTier}
                        </span>
                      )}
                    </div>
                    {!packet.valueContext.selectedIsTopValueItem && packet.valueContext.topValueItemText && (
                      <div className="text-xs text-gray-400">
                        Highest-ranked item in assessment: <span className="text-gray-300">{packet.valueContext.topValueItemText}</span>
                      </div>
                    )}
                    {packet.valueContext.rationale.length > 0 && (
                      <ul className="space-y-1">
                        {packet.valueContext.rationale.map(reason => (
                          <li key={reason} className="flex items-start gap-2 text-sm text-gray-300">
                            <span className="text-emerald-400 flex-shrink-0 mt-0.5">•</span>
                            <span>{reason}</span>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                </>
              )}

              {packet.constraints.length > 0 && (
                <>
                  <SectionHeader title="Constraints" />
                  <div className="space-y-1.5">
                    {packet.constraints.map((constraint, i) => (
                      <div key={`${constraint.source}-${i}`} className="rounded border border-gray-700/60 bg-gray-800/40 px-3 py-2">
                        <div className="flex items-start gap-2">
                          <span className="px-2 py-0.5 rounded border border-gray-700 bg-gray-900/70 text-[11px] text-gray-300 uppercase tracking-wide flex-shrink-0">
                            {CONSTRAINT_SOURCE_LABELS[constraint.source] ?? constraint.source}
                          </span>
                          <span className="text-sm text-gray-300">{constraint.text}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </>
              )}

              {/* Follow-up candidates */}
              {packet.followUpCandidates.length > 0 && (
                <>
                  <SectionHeader title="Follow-up Candidates" />
                  <div className="space-y-1.5">
                    {packet.followUpCandidates.map((c, i) => (
                      <div key={i} className="bg-gray-800/40 border border-gray-700/60 rounded px-3 py-2 text-sm">
                        <span className="text-gray-300">{c.text}</span>
                        <span className="text-xs text-gray-500 ml-2">({c.section})</span>
                      </div>
                    ))}
                  </div>
                </>
              )}

              {/* Documentation findings */}
              {packet.docFindings.length > 0 && (
                <>
                  <SectionHeader title="Documentation Findings" />
                  <div className="space-y-1.5">
                    {packet.docFindings.map((f, i) => (
                      <div
                        key={i}
                        className={`rounded border px-3 py-2 text-xs ${SEVERITY_BG[f.severity] ?? SEVERITY_BG['info']}`}
                      >
                        <div className="flex items-start gap-2">
                          <span className={`font-semibold uppercase flex-shrink-0 ${SEVERITY_COLORS[f.severity] ?? 'text-gray-400'}`}>
                            [{f.severity}]
                          </span>
                          <div>
                            <div className="text-gray-200 mb-0.5">{f.message}</div>
                            <div className="text-gray-400">→ {f.recommendedAction}</div>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </>
              )}

              {/* Acceptance criteria */}
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

              {/* Guardrails */}
              <SectionHeader title="Guardrails" />
              <div className="bg-gray-800/40 border border-gray-700/60 rounded-lg p-3">
                <ul className="space-y-1">
                  {packet.guardrails.map((g, i) => (
                    <li key={i} className="flex items-start gap-2 text-sm text-gray-300">
                      <span className="text-yellow-500 flex-shrink-0 mt-0.5">⚠</span>
                      <span>{g.rule}</span>
                    </li>
                  ))}
                </ul>
              </div>
            </div>
          )}

          {/* Prompt tab */}
          {!loading && !error && packet && activeTab === 'prompt' && (
            <div>
              <div className="flex items-center justify-between mb-3">
                <p className="text-sm text-gray-400">
                  Structured prompt with README, roadmap, assessment, and value context. Review before dispatch.
                </p>
                <button
                  onClick={handleCopyPrompt}
                  className="px-3 py-1.5 text-xs bg-gray-700 hover:bg-gray-600 text-gray-200 rounded border border-gray-600 transition-colors flex items-center gap-1.5"
                >
                  {copied ? '✓ Copied' : 'Copy'}
                </button>
              </div>
              <pre className="bg-gray-800 border border-gray-700 rounded-lg p-4 text-xs text-gray-200 whitespace-pre-wrap font-mono leading-relaxed overflow-x-auto">
                {packet.generatedPrompt}
              </pre>
              {packet.runSummaryPath && (
                <div className="mt-2 text-xs text-gray-600">
                  Packet ID: {packet.runId}
                </div>
              )}
            </div>
          )}

          {/* History tab */}
          {activeTab === 'history' && (
            <div>
              {historyLoading && (
                <div className="flex items-center gap-3 py-8 text-gray-400 justify-center">
                  <SpinnerIcon className="w-4 h-4 animate-spin" />
                  <span>Loading history…</span>
                </div>
              )}
              {!historyLoading && history.length === 0 && (
                <div className="text-center py-8 text-gray-500 text-sm">
                  No task history found for this repository.
                </div>
              )}
              {!historyLoading && history.length > 0 && (
                <div className="space-y-2">
                  {history.map(item => (
                    <div key={item.runId} className="bg-gray-800/50 border border-gray-700 rounded-lg p-3">
                      <div className="flex items-start justify-between gap-2 mb-1.5">
                        <div className="flex-1 min-w-0">
                          <div className="text-sm text-white font-medium truncate">
                            {item.roadmapItem || '(no task recorded)'}
                          </div>
                          {item.repoName && (
                            <div className="text-xs text-gray-400 mt-0.5">{item.repoName}</div>
                          )}
                        </div>
                        <span className={`text-xs font-semibold flex-shrink-0 ${STATUS_COLORS[item.status] ?? 'text-gray-400'}`}>
                          {item.status}
                        </span>
                      </div>
                      <div className="flex flex-wrap gap-x-4 gap-y-0.5 text-xs text-gray-500">
                        {item.startedAt && (
                          <span>Started: {new Date(item.startedAt).toLocaleString()}</span>
                        )}
                        {item.completedAt && (
                          <span>Completed: {new Date(item.completedAt).toLocaleString()}</span>
                        )}
                        {item.roadmapPath && (
                          <span className="truncate max-w-xs" title={item.roadmapPath}>
                            {item.roadmapPath.split(/[\\/]/).pop()}
                          </span>
                        )}
                      </div>
                      {item.error && (
                        <div className="mt-1.5 text-xs text-red-400 bg-red-900/20 rounded px-2 py-1">
                          {item.error}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Footer — Lane 0.17: from the Dispatch Board this modal is the
            confirm step, so it carries the dispatch action instead of
            dead-ending at Copy/Close. */}
        <div className="px-5 py-3 border-t border-gray-700 flex items-center justify-end gap-3 flex-shrink-0">
          {dispatchError && (
            <span className="text-sm text-red-400 flex-1 text-left" role="alert">
              {dispatchError}
            </span>
          )}
          {dispatched && (
            <span className="text-sm text-green-400 flex-1 text-left">
              ✓ Dispatched to a lane — track it on the Dispatch Board.
            </span>
          )}
          <button
            onClick={onClose}
            className="px-4 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded border border-gray-600 transition-colors"
          >
            Close
          </button>
          {onDispatch && packet && !loading && !error && !dispatched && (
            <button
              onClick={() => { void handleDispatch(); }}
              disabled={dispatching}
              className="px-4 py-1.5 text-sm bg-blue-700 hover:bg-blue-600 text-white rounded border border-blue-600 disabled:opacity-50 transition-colors flex items-center gap-1.5"
            >
              {dispatching ? <SpinnerIcon className="w-3.5 h-3.5 animate-spin" /> : null}
              Dispatch to Lane
            </button>
          )}
        </div>
      </div>
    </div>
  );
};

export default CopilotTaskPreviewModal;
