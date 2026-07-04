import React, { useEffect, useState } from 'react';
import { type DocReviewRunRequest } from '../types';

interface DocReviewModalProps {
  isOpen: boolean;
  onClose: () => void;
  onRun: (request: DocReviewRunRequest) => Promise<void>;
  defaultRootPath?: string;
  defaultDepth?: number;
  defaultTargetRepo?: string;
  lockTargetRepo?: boolean;
}

const DocReviewModal: React.FC<DocReviewModalProps> = ({ isOpen, onClose, onRun, defaultRootPath, defaultDepth, defaultTargetRepo, lockTargetRepo }) => {
  const [rootPath, setRootPath] = useState(defaultRootPath ?? 'G:\\Development');
  const [maxDepth, setMaxDepth] = useState(defaultDepth ?? 2);
  const [outDir, setOutDir] = useState('');
  const [targetRepo, setTargetRepo] = useState('');
  const [generateQueue, setGenerateQueue] = useState(true);
  const [generateBatchPlan, setGenerateBatchPlan] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen) {
      return;
    }

    if (defaultRootPath) {
      setRootPath(defaultRootPath);
    }
    if (typeof defaultDepth === 'number') {
      setMaxDepth(defaultDepth);
    }
    if (defaultTargetRepo) {
      setTargetRepo(defaultTargetRepo);
    }
  }, [isOpen, defaultRootPath, defaultDepth, defaultTargetRepo]);

  if (!isOpen) {
    return null;
  }

  const normalizeTargetRepo = (value: string): string | undefined => {
    const trimmed = value.trim();
    if (!trimmed) {
      return undefined;
    }

    const cleaned = trimmed.replace(/[\\/]+$/, '');
    const segments = cleaned.split(/[\\/]+/).filter(Boolean);
    return segments.length > 0 ? segments[segments.length - 1] : cleaned;
  };

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError(null);

    const normalizedTargetRepo = normalizeTargetRepo(targetRepo);
    if (generateBatchPlan && !normalizedTargetRepo) {
      setError('Target repository is required when batch plan generation is enabled.');
      return;
    }

    setSubmitting(true);
    try {
      await onRun({
        rootPath: rootPath.trim(),
        maxDepth,
        outDir: outDir.trim() || undefined,
        targetRepo: normalizedTargetRepo,
        generateQueue,
        generateBatchPlan
      });
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Doc review run failed.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <>
      <div className="fixed inset-0 bg-black/60 z-30" onClick={onClose} />
      <div className="fixed inset-0 z-40 flex items-center justify-center p-4">
        <div className="w-full max-w-2xl rounded-lg border border-gray-700 bg-gray-900 shadow-2xl">
          <div className="flex items-center justify-between border-b border-gray-700 px-5 py-4">
            <h2 className="text-lg font-semibold text-gray-100">Doc Review Inventory</h2>
            <button onClick={onClose} className="rounded p-1 text-gray-400 hover:bg-gray-800 hover:text-white">
              <span aria-hidden>×</span>
            </button>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4 px-5 py-4">
            <div>
              <label className="mb-1 block text-sm text-gray-300">Root Path</label>
              <input
                value={rootPath}
                onChange={(e) => setRootPath(e.target.value)}
                className="w-full rounded border border-gray-600 bg-gray-800 px-3 py-2 text-sm text-white"
                required
              />
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div>
                <label className="mb-1 block text-sm text-gray-300">Max Depth</label>
                <input
                  type="number"
                  min={1}
                  max={10}
                  value={maxDepth}
                  onChange={(e) => setMaxDepth(Number(e.target.value))}
                  className="w-full rounded border border-gray-600 bg-gray-800 px-3 py-2 text-sm text-white"
                />
              </div>
              <div>
                <label className="mb-1 block text-sm text-gray-300">Output Directory (Optional)</label>
                <input
                  value={outDir}
                  onChange={(e) => setOutDir(e.target.value)}
                  placeholder="defaults to backend/output/docreview-adapter"
                  className="w-full rounded border border-gray-600 bg-gray-800 px-3 py-2 text-sm text-white"
                />
              </div>
            </div>

            <div className="space-y-2 rounded border border-gray-700 bg-gray-800/50 px-3 py-3">
              <label className="flex items-center gap-2 text-sm text-gray-200">
                <input type="checkbox" checked={generateQueue} onChange={(e) => setGenerateQueue(e.target.checked)} />
                Generate queue artifacts
              </label>
              <label className="flex items-center gap-2 text-sm text-gray-200">
                <input type="checkbox" checked={generateBatchPlan} onChange={(e) => setGenerateBatchPlan(e.target.checked)} />
                Generate per-repo batch plan
              </label>
              <div>
                <label className="mb-1 block text-sm text-gray-300">Target Repo (for batch plan)</label>
                <input
                  value={targetRepo}
                  onChange={(e) => setTargetRepo(e.target.value)}
                  placeholder="e.g. UnifiedAIToolbox (path also accepted)"
                  className="w-full rounded border border-gray-600 bg-gray-800 px-3 py-2 text-sm text-white"
                  disabled={Boolean(lockTargetRepo) || !generateBatchPlan}
                />
                {lockTargetRepo && <p className="mt-1 text-xs text-gray-400">Target repository is locked when launched from a repository row action.</p>}
              </div>
            </div>

            {error && <div className="rounded border border-red-700 bg-red-900/30 px-3 py-2 text-sm text-red-200">{error}</div>}

            <div className="flex justify-end gap-3 pt-2">
              <button type="button" onClick={onClose} className="rounded border border-gray-600 px-4 py-2 text-sm text-gray-200 hover:bg-gray-800">
                Cancel
              </button>
              <button type="submit" disabled={submitting} className="rounded bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-500 disabled:opacity-50">
                {submitting ? 'Running...' : 'Run Doc Review'}
              </button>
            </div>
          </form>
        </div>
      </div>
    </>
  );
};

export default DocReviewModal;
