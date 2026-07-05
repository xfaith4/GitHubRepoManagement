import React, { useState, useEffect, useCallback } from 'react';
import {
  type RoadmapRepairPreview,
  type RoadmapRepairAction,
  type RoadmapRepairHistoryItem,
  type RoadmapMaturityLevel,
} from '../types';
import { previewRoadmapRepair, applyRoadmapRepair, getRoadmapRepairHistory, submitRoadmapRepairPr, type RoadmapRepairPrResult } from '../services/apiClient';
import { SpinnerIcon } from './icons';

interface RoadmapRepairModalProps {
  isOpen: boolean;
  repoName: string | null;
  onClose: () => void;
  onRepairApplied?: () => void;
}

// ---------------------------------------------------------------------------
// Shared display helpers
// ---------------------------------------------------------------------------

const MATURITY_COLORS: Record<RoadmapMaturityLevel, string> = {
  'L0-Absent': 'bg-gray-800 text-gray-400 border-gray-600',
  'L1-Informal': 'bg-red-900/40 text-red-300 border-red-700/40',
  'L2-Structured': 'bg-orange-900/40 text-orange-300 border-orange-700/40',
  'L3-Contract-Ready': 'bg-yellow-900/40 text-yellow-300 border-yellow-700/40',
  'L4-Orchestration-Ready': 'bg-green-900/40 text-green-300 border-green-700/40',
};

const SEVERITY_TEXT: Record<string, string> = {
  critical: 'text-red-400',
  warning: 'text-yellow-400',
  info: 'text-blue-400',
};

const SEVERITY_BG: Record<string, string> = {
  critical: 'bg-red-900/30 border-red-700/40',
  warning: 'bg-yellow-900/30 border-yellow-700/40',
  info: 'bg-blue-900/20 border-blue-700/30',
};

function MaturityBadge({ level }: { level: RoadmapMaturityLevel }) {
  const cls = MATURITY_COLORS[level] ?? MATURITY_COLORS['L0-Absent'];
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded border text-xs font-medium ${cls}`}>
      {level}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Diff view — side-by-side with scrollable panels
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
// Repair action list
// ---------------------------------------------------------------------------

function ActionRow({ action }: { action: RoadmapRepairAction }) {
  return (
    <div className={`rounded border px-3 py-2 text-sm ${SEVERITY_BG[action.severity] ?? SEVERITY_BG.info}`}>
      <div className="flex items-start gap-2">
        <span className={`mt-0.5 font-medium text-xs uppercase tracking-wide w-16 flex-shrink-0 ${SEVERITY_TEXT[action.severity] ?? ''}`}>
          {action.severity}
        </span>
        <div className="flex-1">
          <div className="text-gray-200">{action.description}</div>
          <div className="text-xs text-gray-500 mt-0.5">Affects: {action.affectsSection}</div>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// History tab
// ---------------------------------------------------------------------------

function HistoryTab({ repoName }: { repoName: string }) {
  const [loading, setLoading] = useState(true);
  const [items, setItems] = useState<RoadmapRepairHistoryItem[]>([]);

  useEffect(() => {
    let cancelled = false;
    getRoadmapRepairHistory(20)
      .then(all => {
        if (cancelled) return;
        setItems(all.filter(h => h.repoName === repoName));
      })
      .catch(() => { if (!cancelled) setItems([]); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [repoName]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8 gap-2 text-gray-400">
        <SpinnerIcon className="w-4 h-4 animate-spin" />
        <span className="text-sm">Loading history…</span>
      </div>
    );
  }

  if (items.length === 0) {
    return (
      <p className="text-sm text-gray-500 py-4 text-center">No repair history for this repository.</p>
    );
  }

  return (
    <div className="space-y-2">
      {items.map((item, i) => (
        <div key={item.previewId ?? i} className="rounded border border-gray-700/50 bg-gray-800/40 px-3 py-2 text-xs">
          <div className="flex items-center justify-between">
            <span className={`font-medium uppercase tracking-wide ${item.event === 'apply' ? 'text-green-400' : 'text-blue-400'}`}>
              {item.event}
            </span>
            <span className="text-gray-500">{new Date(item.timestamp).toLocaleString()}</span>
          </div>
          <div className="text-gray-400 mt-0.5">State: {item.previewState}</div>
          <div className="text-gray-500 mt-0.5 truncate">Preview ID: {item.previewId}</div>
          {item.appliedAt && (
            <div className="text-green-400 mt-0.5">Applied: {new Date(item.appliedAt).toLocaleString()}</div>
          )}
        </div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main modal
// ---------------------------------------------------------------------------

type Tab = 'preview' | 'diff' | 'history';

const RoadmapRepairModal: React.FC<RoadmapRepairModalProps> = ({
  isOpen,
  repoName,
  onClose,
  onRepairApplied,
}) => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [preview, setPreview] = useState<RoadmapRepairPreview | null>(null);
  const [activeTab, setActiveTab] = useState<Tab>('preview');

  // Apply workflow states
  const [applyConfirmVisible, setApplyConfirmVisible] = useState(false);
  const [applying, setApplying] = useState(false);
  const [applyError, setApplyError] = useState<string | null>(null);
  const [applySuccess, setApplySuccess] = useState(false);

  // Editable proposed content
  const [editedProposed, setEditedProposed] = useState('');

  // Release 2.4 — submit-PR (dry-run plan) state
  const [prResult, setPrResult] = useState<RoadmapRepairPrResult | null>(null);
  const [prLoading, setPrLoading] = useState(false);
  const [prError, setPrError] = useState<string | null>(null);

  const handleSubmitPr = useCallback(async () => {
    if (!repoName) return;
    setPrLoading(true);
    setPrError(null);
    try {
      const result = await submitRoadmapRepairPr(repoName, preview?.previewId);
      setPrResult(result);
    } catch (err) {
      setPrError(err instanceof Error ? err.message : 'Failed to build repair PR plan.');
    } finally {
      setPrLoading(false);
    }
  }, [repoName, preview]);

  // Load the preview when modal opens
  useEffect(() => {
    if (!isOpen || !repoName) {
      setPreview(null);
      setError(null);
      setApplyConfirmVisible(false);
      setApplying(false);
      setApplyError(null);
      setApplySuccess(false);
      setEditedProposed('');
      setActiveTab('preview');
      setPrResult(null);
      setPrError(null);
      return;
    }
    let cancelled = false;
    setLoading(true);
    setError(null);

    previewRoadmapRepair(repoName)
      .then(p => {
        if (cancelled) return;
        setPreview(p);
        setEditedProposed(p.proposedContent ?? '');
      })
      .catch(err => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : 'Failed to build repair preview.');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => { cancelled = true; };
  }, [isOpen, repoName]);

  const handleApply = useCallback(async () => {
    if (!preview || !repoName) return;
    setApplying(true);
    setApplyError(null);
    try {
      await applyRoadmapRepair(
        repoName,
        preview.previewId,
        editedProposed,
        preview.roadmapPath ?? undefined,
        preview.originalMaturityLevel,
      );
      setApplySuccess(true);
      setApplyConfirmVisible(false);
      onRepairApplied?.();
    } catch (err) {
      setApplyError(err instanceof Error ? err.message : 'Failed to apply repair.');
    } finally {
      setApplying(false);
    }
  }, [preview, repoName, editedProposed, onRepairApplied]);

  if (!isOpen) return null;

  const canApply =
    preview?.previewState === 'repair-preview-ready' &&
    !applySuccess &&
    !applying;

  return (
    <div
      className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-4"
      onClick={e => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="mobile-sheet bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-full max-w-3xl max-h-[92vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-3.5 border-b border-gray-700/60 flex-shrink-0">
          <div>
            <h2 className="text-base font-semibold text-white">Roadmap Repair Preview</h2>
            {repoName && <p className="text-xs text-gray-400 mt-0.5">{repoName}</p>}
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-white transition-colors p-1 rounded"
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        {/* Tab bar */}
        <div className="flex border-b border-gray-700/60 flex-shrink-0">
          {(['preview', 'diff', 'history'] as Tab[]).map(tab => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-4 py-2 text-sm font-medium transition-colors ${
                activeTab === tab
                  ? 'text-white border-b-2 border-blue-500'
                  : 'text-gray-400 hover:text-gray-200'
              }`}
            >
              {tab === 'preview' ? 'Repair Plan' : tab === 'diff' ? 'Diff Preview' : 'History'}
            </button>
          ))}
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-5 py-4">
          {loading && (
            <div className="flex items-center justify-center py-12 gap-3 text-gray-400">
              <SpinnerIcon className="w-5 h-5 animate-spin" />
              <span className="text-sm">Building repair preview…</span>
            </div>
          )}

          {!loading && error && (
            <div className="rounded border border-red-700/40 bg-red-900/20 px-4 py-3 text-sm text-red-300">
              {error}
            </div>
          )}

          {!loading && !error && preview && activeTab === 'preview' && (
            <div className="space-y-4">
              {/* State banner */}
              {preview.previewState === 'repair-blocked' && (
                <div className="rounded border border-red-700/40 bg-red-900/20 px-4 py-3 text-sm text-red-300">
                  <strong>Repair blocked:</strong> {preview.blockReason}
                </div>
              )}
              {preview.previewState === 'rewrite-not-recommended' && (
                <div className="rounded border border-yellow-700/40 bg-yellow-900/20 px-4 py-3 text-sm text-yellow-300">
                  <strong>Rewrite not recommended:</strong> {preview.blockReason}
                </div>
              )}
              {preview.previewState === 'repair-preview-ready' && (
                <div className="rounded border border-blue-700/40 bg-blue-900/20 px-4 py-3 text-sm text-blue-300">
                  ✓ Repair preview is ready. Review the diff and repair actions below before applying.
                </div>
              )}

              {/* Maturity & stats */}
              <div className="bg-gray-800/60 rounded-lg border border-gray-700/50 p-4">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-gray-300">Current Maturity</span>
                  <MaturityBadge level={preview.originalMaturityLevel} />
                </div>
                <div className="grid grid-cols-3 gap-2 mt-2">
                  {[
                    { label: 'Completed Items', value: preview.completedItemCount, color: 'text-green-400' },
                    { label: 'Pending Items', value: preview.pendingItemCount, color: 'text-yellow-400' },
                    { label: 'Repair Actions', value: preview.repairActions.length, color: 'text-blue-400' },
                  ].map(({ label, value, color }) => (
                    <div key={label} className="bg-gray-800/60 rounded border border-gray-700/50 p-2 text-center">
                      <div className={`text-lg font-bold ${color}`}>{value}</div>
                      <div className="text-xs text-gray-500">{label}</div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Release 2.4 — submit-PR (dry-run plan). Live PR creation is an
                  operator action requiring a git checkout + GitHub write. */}
              <div className="bg-gray-800/60 rounded-lg border border-gray-700/50 p-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-gray-300">Open as pull request</span>
                  <button
                    onClick={handleSubmitPr}
                    disabled={prLoading}
                    className="inline-flex items-center gap-1.5 rounded-md bg-indigo-600 px-3 py-1.5 text-xs font-medium text-white disabled:opacity-50"
                  >
                    {prLoading ? 'Building plan…' : 'Preview repair PR'}
                  </button>
                </div>
                {prError && <div className="mt-2 text-xs text-red-300">{prError}</div>}
                {prResult && (
                  <div className="mt-3 rounded border border-gray-700 bg-gray-900/60 p-3 text-xs text-gray-300 space-y-1">
                    <div><span className="text-gray-500">Branch:</span> <span className="font-mono text-gray-200">{prResult.plan.branch}</span></div>
                    <div><span className="text-gray-500">Base:</span> <span className="font-mono text-gray-200">{prResult.plan.baseBranch}</span></div>
                    <div><span className="text-gray-500">Title:</span> {prResult.plan.title}</div>
                    <div className="text-gray-500 italic">{prResult.note}</div>
                  </div>
                )}
              </div>

              {/* Repair actions */}
              {preview.repairActions.length > 0 && (
                <div>
                  <p className="text-xs font-medium text-gray-400 uppercase tracking-wide mb-2">
                    Repair Actions ({preview.repairActions.length})
                  </p>
                  <div className="space-y-1.5">
                    {preview.repairActions.map((a, i) => (
                      <ActionRow key={a.actionId ?? i} action={a} />
                    ))}
                  </div>
                </div>
              )}

              {/* Apply success banner */}
              {applySuccess && (
                <div className="rounded border border-green-700/40 bg-green-900/20 px-4 py-3 text-sm text-green-300">
                  ✓ Repair applied successfully. The roadmap file has been updated.
                </div>
              )}

              {/* Apply error */}
              {applyError && (
                <div className="rounded border border-red-700/40 bg-red-900/20 px-4 py-3 text-sm text-red-300">
                  {applyError}
                </div>
              )}
            </div>
          )}

          {!loading && !error && preview && activeTab === 'diff' && (
            <div className="space-y-3">
              {preview.previewState !== 'repair-preview-ready' ? (
                <p className="text-sm text-gray-500 py-4 text-center">
                  No diff available — {preview.blockReason ?? 'repair not applicable.'}
                </p>
              ) : (
                <>
                  <DiffView
                    current={preview.currentContent}
                    proposed={editedProposed}
                  />
                  <div className="mt-2">
                    <p className="text-xs font-medium text-gray-400 uppercase tracking-wide mb-1">
                      Edit proposed roadmap (optional)
                    </p>
                    <textarea
                      className="w-full h-48 bg-gray-900/80 border border-gray-700/60 rounded p-2 text-xs font-mono text-gray-200 resize-y focus:outline-none focus:border-blue-600"
                      value={editedProposed}
                      onChange={e => setEditedProposed(e.target.value)}
                      spellCheck={false}
                    />
                    <p className="text-xs text-gray-600 mt-1">
                      You may edit the proposed content above before applying. Completed items (- [x]) must be preserved.
                    </p>
                  </div>
                </>
              )}
            </div>
          )}

          {!loading && !error && repoName && activeTab === 'history' && (
            <HistoryTab repoName={repoName} />
          )}
        </div>

        {/* Footer */}
        <div className="px-5 py-3 border-t border-gray-700/60 flex-shrink-0 flex items-center justify-between gap-3">
          <div className="text-xs text-gray-600">
            {preview && `Preview ID: ${preview.previewId}`}
          </div>
          <div className="flex items-center gap-2">
            {canApply && !applyConfirmVisible && (
              <button
                onClick={() => setApplyConfirmVisible(true)}
                className="px-4 py-1.5 rounded bg-green-700 hover:bg-green-600 text-sm text-white font-medium transition-colors"
              >
                Apply Repair…
              </button>
            )}
            {canApply && applyConfirmVisible && (
              <>
                <span className="text-xs text-yellow-300">Apply this repair to the roadmap file?</span>
                <button
                  onClick={handleApply}
                  disabled={applying}
                  className="px-3 py-1.5 rounded bg-green-700 hover:bg-green-600 disabled:opacity-50 text-sm text-white font-medium transition-colors flex items-center gap-1"
                >
                  {applying && <SpinnerIcon className="w-3.5 h-3.5 animate-spin" />}
                  Confirm Apply
                </button>
                <button
                  onClick={() => setApplyConfirmVisible(false)}
                  className="px-3 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-sm text-gray-200 transition-colors"
                >
                  Cancel
                </button>
              </>
            )}
            <button
              onClick={onClose}
              className="px-4 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-sm text-gray-200 transition-colors"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default RoadmapRepairModal;
