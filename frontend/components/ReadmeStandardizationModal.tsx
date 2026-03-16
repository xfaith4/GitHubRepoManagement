import React, { useState, useCallback } from 'react';
import type { ReadmeStandardizationPreview, ReadmeStandardizationHistoryItem } from '../types';
import { previewReadmeStandardization, applyReadmeStandardization, getReadmeStandardizationHistory } from '../services/apiClient';

interface ReadmeStandardizationModalProps {
  repoName: string;
  repoPath?: string;
  onClose: () => void;
  onApplied?: () => void;
}

type ModalTab = 'preview' | 'diff' | 'history';

const severityBadge = (severity: string): string => {
  if (severity === 'error') return 'bg-red-100 text-red-700 border border-red-200';
  if (severity === 'warning') return 'bg-yellow-100 text-yellow-700 border border-yellow-200';
  return 'bg-blue-50 text-blue-600 border border-blue-200';
};

export const ReadmeStandardizationModal: React.FC<ReadmeStandardizationModalProps> = ({
  repoName,
  repoPath,
  onClose,
  onApplied,
}) => {
  const [activeTab, setActiveTab] = useState<ModalTab>('preview');
  const [preview, setPreview] = useState<ReadmeStandardizationPreview | null>(null);
  const [history, setHistory] = useState<ReadmeStandardizationHistoryItem[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isApplying, setIsApplying] = useState(false);
  const [confirmApply, setConfirmApply] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [applySuccess, setApplySuccess] = useState(false);
  const [editedContent, setEditedContent] = useState<string>('');

  const loadPreview = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const result = await previewReadmeStandardization(repoName, repoPath);
      setPreview(result);
      setEditedContent(result.proposedContent ?? result.currentContent ?? '');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Preview failed');
    } finally {
      setIsLoading(false);
    }
  }, [repoName, repoPath]);

  const loadHistory = useCallback(async () => {
    try {
      const items = await getReadmeStandardizationHistory(25);
      setHistory(items.filter(h => h.repoName === repoName));
    } catch { /* ignore */ }
  }, [repoName]);

  const handleTabChange = useCallback((tab: ModalTab) => {
    setActiveTab(tab);
    if (tab === 'preview' && !preview && !isLoading) loadPreview();
    if (tab === 'history') loadHistory();
  }, [preview, isLoading, loadPreview, loadHistory]);

  // Load preview on mount
  React.useEffect(() => {
    loadPreview();
  }, [loadPreview]);

  const handleApply = useCallback(async () => {
    if (!preview) return;
    setIsApplying(true);
    setError(null);
    try {
      await applyReadmeStandardization(repoName, preview.previewId, editedContent, repoPath);
      setApplySuccess(true);
      setConfirmApply(false);
      if (onApplied) onApplied();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Apply failed');
    } finally {
      setIsApplying(false);
    }
  }, [preview, repoName, editedContent, repoPath, onApplied]);

  const stateLabel = preview?.previewState;
  const isBlocked = stateLabel === 'standardization-blocked';
  const isAlreadyStandard = stateLabel === 'already-standard';
  const canApply = stateLabel === 'standardization-preview-ready' && !applySuccess;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-4xl max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200">
          <div>
            <h2 className="text-lg font-semibold text-gray-900">README Standardization</h2>
            <p className="text-sm text-gray-500 mt-0.5">{repoName}</p>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-2xl leading-none">&times;</button>
        </div>

        {/* Tabs */}
        <div className="flex border-b border-gray-200 px-6">
          {(['preview', 'diff', 'history'] as ModalTab[]).map(tab => (
            <button
              key={tab}
              onClick={() => handleTabChange(tab)}
              className={`py-3 px-4 text-sm font-medium border-b-2 transition-colors capitalize ${
                activeTab === tab
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              {tab === 'diff' ? 'Diff Preview' : tab === 'preview' ? 'Standardization Plan' : 'History'}
            </button>
          ))}
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto p-6">
          {isLoading && (
            <div className="flex items-center justify-center py-12">
              <div className="text-gray-500">Loading preview...</div>
            </div>
          )}

          {error && (
            <div className="bg-red-50 border border-red-200 rounded p-4 text-red-700 text-sm mb-4">
              {error}
            </div>
          )}

          {applySuccess && (
            <div className="bg-green-50 border border-green-200 rounded p-4 text-green-700 text-sm mb-4">
              README standardization applied successfully.
            </div>
          )}

          {!isLoading && activeTab === 'preview' && preview && (
            <div className="space-y-4">
              {/* State badge */}
              <div className="flex items-center gap-3">
                <span className={`px-3 py-1 rounded-full text-xs font-semibold ${
                  isBlocked ? 'bg-red-100 text-red-700' :
                  isAlreadyStandard ? 'bg-green-100 text-green-700' :
                  'bg-blue-100 text-blue-700'
                }`}>
                  {isBlocked ? 'Blocked' : isAlreadyStandard ? 'Already Standard' : 'Ready to Standardize'}
                </span>
                <span className="text-sm text-gray-500">{preview.standardizationActions.length} action(s)</span>
              </div>

              {isBlocked && preview.blockReason && (
                <div className="bg-red-50 border border-red-200 rounded p-3 text-red-600 text-sm">
                  {preview.blockReason}
                </div>
              )}

              {isAlreadyStandard && (
                <div className="bg-green-50 border border-green-200 rounded p-3 text-green-700 text-sm">
                  This README already meets all standardization requirements.
                </div>
              )}

              {/* Actions list */}
              {preview.standardizationActions.length > 0 && (
                <div className="space-y-2">
                  <h3 className="text-sm font-semibold text-gray-700">Standardization Actions</h3>
                  {preview.standardizationActions.map((action, i) => (
                    <div key={i} className="flex items-start gap-3 p-3 rounded border border-gray-100 bg-gray-50">
                      <span className={`px-2 py-0.5 rounded text-xs font-semibold ${severityBadge(action.severity)}`}>
                        {action.severity}
                      </span>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm text-gray-700">{action.description}</p>
                        <p className="text-xs text-gray-400 mt-0.5">{action.actionId}</p>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {!isLoading && activeTab === 'diff' && preview && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <h3 className="text-xs font-semibold text-gray-500 uppercase mb-2">Current README</h3>
                  <pre className="bg-gray-50 border border-gray-200 rounded p-3 text-xs overflow-auto max-h-96 whitespace-pre-wrap">
                    {preview.currentContent || '(empty)'}
                  </pre>
                </div>
                <div>
                  <h3 className="text-xs font-semibold text-gray-500 uppercase mb-2">Proposed README</h3>
                  <textarea
                    className="w-full bg-blue-50 border border-blue-200 rounded p-3 text-xs max-h-96 font-mono resize-none"
                    rows={20}
                    value={editedContent}
                    onChange={e => setEditedContent(e.target.value)}
                  />
                </div>
              </div>
            </div>
          )}

          {activeTab === 'history' && (
            <div className="space-y-2">
              {history.length === 0 ? (
                <p className="text-sm text-gray-500">No standardization history for this repo.</p>
              ) : (
                history.map((item, i) => (
                  <div key={i} className="p-3 rounded border border-gray-200 text-sm">
                    <div className="flex items-center gap-2">
                      <span className={`px-2 py-0.5 rounded text-xs ${item.event === 'apply' ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'}`}>
                        {item.event}
                      </span>
                      <span className="text-gray-500">{new Date(item.timestamp).toLocaleString()}</span>
                    </div>
                    <p className="text-gray-400 text-xs mt-1">ID: {item.previewId}</p>
                  </div>
                ))
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        {canApply && activeTab !== 'history' && (
          <div className="px-6 py-4 border-t border-gray-200 flex justify-end gap-3">
            {!confirmApply ? (
              <>
                <button onClick={onClose} className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800">
                  Cancel
                </button>
                <button
                  onClick={() => setConfirmApply(true)}
                  className="px-4 py-2 bg-blue-600 text-white text-sm rounded hover:bg-blue-700"
                >
                  Apply Standardization
                </button>
              </>
            ) : (
              <>
                <button onClick={() => setConfirmApply(false)} className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800">
                  Cancel
                </button>
                <button
                  onClick={handleApply}
                  disabled={isApplying}
                  className="px-4 py-2 bg-green-600 text-white text-sm rounded hover:bg-green-700 disabled:opacity-50"
                >
                  {isApplying ? 'Applying...' : 'Confirm Apply'}
                </button>
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
