import React, { useState, useEffect } from 'react';
import { type CopilotTaskPacket, type CopilotTaskHistoryItem } from '../types';
import { previewCopilotTaskPacket, getCopilotTaskHistory } from '../services/apiClient';
import { SpinnerIcon } from './icons';

interface CopilotTaskPreviewModalProps {
  isOpen: boolean;
  repoName: string | null;
  roadmapPath?: string;
  onClose: () => void;
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
}) => {
  const [activeTab, setActiveTab] = useState<'packet' | 'prompt' | 'history'>('packet');
  const [packet, setPacket] = useState<CopilotTaskPacket | null>(null);
  const [history, setHistory] = useState<CopilotTaskHistoryItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!isOpen || !repoName) return;
    setPacket(null);
    setError(null);
    setActiveTab('packet');
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

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-4">
      <div className="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-full max-w-3xl max-h-[90vh] flex flex-col">
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

          {/* Error */}
          {!loading && error && (
            <div className="bg-red-900/30 border border-red-700/40 rounded-lg px-4 py-3 text-sm text-red-300">
              <div className="font-semibold mb-1">Failed to build task packet</div>
              <div className="text-red-400/80">{error}</div>
              <div className="mt-2 text-xs text-red-400/60">
                Ensure a roadmap scan has been run (Work Queue → Scan All) and this repository has pending roadmap items.
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
                <div className="flex gap-2">
                  <span className="text-gray-400 w-28 flex-shrink-0">Packet ID</span>
                  <span className="text-gray-500 font-mono text-xs">{packet.runId}</span>
                </div>
              </div>

              {/* Selected roadmap item */}
              <SectionHeader title="Selected Roadmap Item" />
              <div className="bg-indigo-900/20 border border-indigo-700/40 rounded-lg p-3 space-y-2">
                <div className="text-white font-medium text-sm">{packet.selectedRoadmapItem.text}</div>
                <div className="text-xs text-indigo-400/80">Section: {packet.selectedRoadmapItem.section}</div>
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
                  Structured prompt ready for Copilot. Review before dispatch.
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

        {/* Footer */}
        <div className="px-5 py-3 border-t border-gray-700 flex items-center justify-end gap-2 flex-shrink-0">
          <button
            onClick={onClose}
            className="px-4 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded border border-gray-600 transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
};

export default CopilotTaskPreviewModal;
