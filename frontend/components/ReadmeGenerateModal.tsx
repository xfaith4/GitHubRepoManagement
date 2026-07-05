import React, { useState, useEffect, useCallback } from 'react';
import { type ReadmeGenerationResult, type ReadmeGenerationHistoryItem } from '../types';
import { generateReadme, applyGeneratedReadme, getReadmeGenerationHistory } from '../services/apiClient';
import { SpinnerIcon } from './icons';

interface ReadmeGenerateModalProps {
  isOpen: boolean;
  repoName: string | null;
  localPath?: string | null;
  onClose: () => void;
  onApplied?: () => void;
}

type GeneratePhase = 'idle' | 'generating' | 'review' | 'applying' | 'done' | 'error';
type ReviewTab = 'preview' | 'history';

export default function ReadmeGenerateModal({
  isOpen,
  repoName,
  localPath,
  onClose,
  onApplied,
}: ReadmeGenerateModalProps) {
  const [phase, setPhase] = useState<GeneratePhase>('idle');
  const [errorMsg, setErrorMsg] = useState<string>('');
  const [result, setResult] = useState<ReadmeGenerationResult | null>(null);
  const [editedContent, setEditedContent] = useState<string>('');
  const [appliedPath, setAppliedPath] = useState<string>('');
  const [activeTab, setActiveTab] = useState<ReviewTab>('preview');
  const [history, setHistory] = useState<ReadmeGenerationHistoryItem[]>([]);
  const [showApplyConfirm, setShowApplyConfirm] = useState<boolean>(false);

  const run = useCallback(async () => {
    if (!repoName) return;
    setPhase('generating');
    setErrorMsg('');
    setResult(null);
    setEditedContent('');
    setShowApplyConfirm(false);
    setActiveTab('preview');
    try {
      const r = await generateReadme(repoName, localPath ?? undefined);
      setResult(r);
      setEditedContent(r.previewContent);
      setPhase('review');
      // Load history in the background
      try {
        const h = await getReadmeGenerationHistory(50);
        setHistory(h.filter(item => item.repoName === repoName));
      } catch {
        // History is non-critical
      }
    } catch (err: any) {
      setErrorMsg(err?.message ?? 'Unknown error');
      setPhase('error');
    }
  }, [repoName, localPath]);

  useEffect(() => {
    if (isOpen && repoName) {
      run();
    } else if (!isOpen) {
      setPhase('idle');
      setErrorMsg('');
      setResult(null);
      setEditedContent('');
      setAppliedPath('');
      setShowApplyConfirm(false);
      setActiveTab('preview');
      setHistory([]);
    }
  }, [isOpen, repoName]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleApply = useCallback(async () => {
    if (!repoName || !result) return;
    setShowApplyConfirm(false);
    setPhase('applying');
    try {
      const applyResult = await applyGeneratedReadme(
        repoName,
        result.generationId,
        editedContent,
        localPath ?? undefined
      );
      setAppliedPath(applyResult.readmePath);
      setPhase('done');
      onApplied?.();
    } catch (err: any) {
      setErrorMsg(err?.message ?? 'Unknown error');
      setPhase('error');
    }
  }, [repoName, result, editedContent, localPath, onApplied]);

  if (!isOpen || !repoName) return null;

  const is412 =
    phase === 'error' &&
    (errorMsg.includes('412') ||
      errorMsg.toLowerCase().includes('not configured') ||
      errorMsg.toLowerCase().includes('copilotapikey') ||
      errorMsg.toLowerCase().includes('github_token'));

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70">
      <div className="mobile-sheet relative w-full max-w-3xl mx-4 rounded-xl bg-gray-900 border border-gray-700 shadow-2xl flex flex-col max-h-[90vh]">

        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-700 flex-shrink-0">
          <div>
            <div className="text-base font-semibold text-white">Generate README</div>
            <div className="text-xs text-gray-400 mt-0.5">{repoName}</div>
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-white transition-colors text-xl leading-none"
            aria-label="Close"
          >
            ×
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-6 py-5">

          {/* Generating */}
          {phase === 'generating' && (
            <div className="flex flex-col items-center justify-center py-16 gap-4">
              <SpinnerIcon className="w-8 h-8 text-emerald-400 animate-spin" />
              <div className="text-gray-300 text-sm">Analyzing repository and generating README…</div>
            </div>
          )}

          {/* Applying */}
          {phase === 'applying' && (
            <div className="flex flex-col items-center justify-center py-16 gap-4">
              <SpinnerIcon className="w-8 h-8 text-emerald-400 animate-spin" />
              <div className="text-gray-300 text-sm">Writing README.md to repository…</div>
            </div>
          )}

          {/* Done */}
          {phase === 'done' && (
            <div className="rounded-lg bg-green-900/30 border border-green-700/50 px-5 py-4">
              <div className="text-sm font-semibold text-green-300 mb-1">README.md written successfully</div>
              {appliedPath && (
                <div className="text-xs text-gray-400 font-mono break-all mt-1">{appliedPath}</div>
              )}
              <div className="text-xs text-gray-400 mt-3">
                Re-run the docs audit to clear the missing-README finding.
              </div>
            </div>
          )}

          {/* Error */}
          {phase === 'error' && (
            <div className="rounded-lg bg-red-900/30 border border-red-700/50 px-5 py-4">
              {is412 ? (
                <>
                  <div className="text-sm font-semibold text-red-300 mb-2">
                    GitHub Copilot API key not configured
                  </div>
                  <div className="text-xs text-gray-300 space-y-1.5">
                    <p>To enable README generation, configure one of the following:</p>
                    <ul className="list-disc list-inside space-y-1 text-gray-400">
                      <li>Add <span className="font-mono text-yellow-300">readme.copilotApiKey</span> to Settings</li>
                      <li>Set the env var named by <span className="font-mono text-yellow-300">readme.copilotApiKeyEnvVar</span> in Settings</li>
                      <li>Set <span className="font-mono text-yellow-300">GITHUB_TOKEN</span> with Copilot access</li>
                      <li>Authenticate with <span className="font-mono text-yellow-300">gh auth login</span> (Copilot plan required)</li>
                    </ul>
                    <p className="text-gray-500 mt-2">
                      Default endpoint: <span className="font-mono">https://api.githubcopilot.com/chat/completions</span>
                    </p>
                  </div>
                </>
              ) : (
                <>
                  <div className="text-sm font-semibold text-red-300 mb-2">Generation failed</div>
                  <div className="text-xs text-gray-400 font-mono break-all">{errorMsg}</div>
                </>
              )}
              <button
                onClick={run}
                className="mt-4 px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-white rounded transition-colors"
              >
                Retry
              </button>
            </div>
          )}

          {/* Review */}
          {phase === 'review' && result && (
            <div className="flex flex-col gap-4">
              {/* Tab bar */}
              <div className="flex gap-1 border-b border-gray-700 pb-0">
                {(['preview', 'history'] as ReviewTab[]).map(tab => (
                  <button
                    key={tab}
                    onClick={() => setActiveTab(tab)}
                    className={`px-3 py-1.5 text-xs font-medium rounded-t transition-colors ${
                      activeTab === tab
                        ? 'bg-gray-800 text-white border border-gray-600 border-b-gray-800 -mb-px'
                        : 'text-gray-400 hover:text-gray-200'
                    }`}
                  >
                    {tab.charAt(0).toUpperCase() + tab.slice(1)}
                  </button>
                ))}
              </div>

              {/* Preview tab */}
              {activeTab === 'preview' && (
                <div className="flex flex-col gap-3">
                  {/* Context banner */}
                  <div className="rounded bg-gray-800 border border-gray-700 px-3 py-2 text-xs text-gray-400">
                    <span className="text-gray-300 font-medium">Generated from:</span>{' '}
                    <span className="capitalize">{result.repoType}</span> repo · {result.contextSummary}
                  </div>

                  {/* Editable content */}
                  <textarea
                    value={editedContent}
                    onChange={e => setEditedContent(e.target.value)}
                    rows={28}
                    className="w-full rounded bg-gray-800 border border-gray-700 text-gray-200 text-xs font-mono p-3 resize-y focus:outline-none focus:border-emerald-600 focus:ring-1 focus:ring-emerald-600"
                    spellCheck={false}
                  />

                  {/* Apply confirmation panel */}
                  {showApplyConfirm ? (
                    <div className="rounded-lg bg-gray-800 border border-yellow-700/50 px-4 py-3">
                      <div className="text-xs text-yellow-300 font-semibold mb-1">⚠ Confirm write</div>
                      <div className="text-xs text-gray-300 mb-3">
                        This will write <span className="font-mono text-white">README.md</span> to{' '}
                        <span className="font-mono text-gray-400">{localPath ?? result.localPath}</span>.
                        This cannot be undone.
                      </div>
                      <div className="flex gap-2">
                        <button
                          onClick={handleApply}
                          className="px-3 py-1.5 text-sm bg-emerald-700 hover:bg-emerald-600 text-white rounded transition-colors"
                        >
                          Confirm — Write README.md
                        </button>
                        <button
                          onClick={() => setShowApplyConfirm(false)}
                          className="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded transition-colors"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  ) : (
                    <div className="flex justify-end">
                      <button
                        onClick={() => setShowApplyConfirm(true)}
                        disabled={!editedContent.trim()}
                        className="px-4 py-2 text-sm bg-emerald-700 hover:bg-emerald-600 disabled:opacity-50 disabled:cursor-not-allowed text-white rounded transition-colors"
                      >
                        Apply to Repository
                      </button>
                    </div>
                  )}
                </div>
              )}

              {/* History tab */}
              {activeTab === 'history' && (
                <div>
                  {history.length === 0 ? (
                    <div className="text-xs text-gray-500 py-4">No generation history for this repository.</div>
                  ) : (
                    <div className="flex flex-col gap-2">
                      {history.map((item, idx) => (
                        <div
                          key={item.generationId ?? idx}
                          className="rounded bg-gray-800 border border-gray-700 px-3 py-2 text-xs"
                        >
                          <div className="flex items-center gap-2 mb-1">
                            <span className={`px-1.5 py-0.5 rounded text-xs font-medium ${
                              item.appliedAt
                                ? 'bg-green-900/40 text-green-300 border border-green-700/40'
                                : 'bg-blue-900/40 text-blue-300 border border-blue-700/40'
                            }`}>
                              {item.appliedAt ? 'Applied' : 'Generated'}
                            </span>
                            <span className="text-gray-400 font-mono">{item.generationId}</span>
                          </div>
                          {item.repoType && (
                            <div className="text-gray-500">Type: <span className="text-gray-300 capitalize">{item.repoType}</span></div>
                          )}
                          {item.appliedAt && (
                            <div className="text-gray-500">Applied: <span className="text-gray-300">{new Date(item.appliedAt).toLocaleString()}</span></div>
                          )}
                          {item.generatedAt && (
                            <div className="text-gray-500">Generated: <span className="text-gray-300">{new Date(item.generatedAt).toLocaleString()}</span></div>
                          )}
                          {item.readmePath && (
                            <div className="text-gray-500 font-mono break-all">{item.readmePath}</div>
                          )}
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end px-6 py-3 border-t border-gray-700 flex-shrink-0">
          {phase === 'done' ? (
            <button
              onClick={onClose}
              className="px-4 py-2 text-sm bg-gray-700 hover:bg-gray-600 text-white rounded transition-colors"
            >
              Close
            </button>
          ) : (
            <button
              onClick={onClose}
              className="px-4 py-2 text-sm text-gray-400 hover:text-white transition-colors"
              disabled={phase === 'applying'}
            >
              {phase === 'applying' ? 'Please wait…' : 'Cancel'}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
