import React, { useState, useEffect, useCallback } from 'react';
import { type RoadmapContent } from '../types';
import { getRoadmapContent, triggerRoadmapScan } from '../services/apiClient';

interface RoadmapViewerModalProps {
  isOpen: boolean;
  repoName: string | null;
  onClose: () => void;
  onScanComplete?: (count: number) => void;
}

const RoadmapViewerModal: React.FC<RoadmapViewerModalProps> = ({ isOpen, repoName, onClose, onScanComplete }) => {
  const [content, setContent] = useState<RoadmapContent | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const [scanMessage, setScanMessage] = useState<string | null>(null);

  const loadContent = useCallback(async (name: string) => {
    setLoading(true);
    setError(null);
    setContent(null);
    try {
      const result = await getRoadmapContent(name);
      setContent(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load roadmap content.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (isOpen && repoName) {
      loadContent(repoName);
      setScanMessage(null);
    }
  }, [isOpen, repoName, loadContent]);

  const handleScanAll = async () => {
    setScanning(true);
    setScanMessage('Scanning all repositories for ROADMAP files...');
    try {
      const result = await triggerRoadmapScan();
      setScanMessage(`Scan complete. Found ${result.count} ROADMAP ${result.count === 1 ? 'file' : 'files'} across your repositories.`);
      if (onScanComplete) onScanComplete(result.count);
    } catch (err) {
      setScanMessage('Scan failed: ' + (err instanceof Error ? err.message : 'Unknown error'));
    } finally {
      setScanning(false);
    }
  };

  if (!isOpen) return null;

  const formatDate = (iso: string) => {
    try { return new Date(iso).toLocaleString(); } catch { return iso; }
  };

  const formatSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
      <div className="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-full max-w-4xl max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-700 flex-shrink-0">
          <div className="flex items-center gap-3">
            <span className="text-lg font-semibold text-gray-100">ROADMAP</span>
            {repoName && (
              <span className="text-sm text-blue-400 font-mono bg-blue-900/30 px-2 py-0.5 rounded">{repoName}</span>
            )}
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={handleScanAll}
              disabled={scanning}
              title="Re-scan all repos for ROADMAP files"
              className="text-xs px-3 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-gray-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {scanning ? 'Scanning...' : 'Scan All ROADMAPs'}
            </button>
            <button
              onClick={() => repoName && loadContent(repoName)}
              disabled={loading}
              title="Refresh roadmap content"
              className="text-xs px-3 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-gray-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              Refresh
            </button>
            <span
              title="AI Agent — Phase 2 coming soon"
              className="text-xs px-3 py-1.5 rounded bg-gray-800 text-gray-500 cursor-not-allowed border border-gray-700 select-none"
            >
              Run AI Agent
            </span>
            <button
              onClick={onClose}
              className="ml-1 text-gray-400 hover:text-gray-100 transition-colors text-xl leading-none"
              aria-label="Close"
            >
              ×
            </button>
          </div>
        </div>

        {/* Scan message bar */}
        {scanMessage && (
          <div className={`px-5 py-2 text-xs border-b border-gray-700 flex-shrink-0 ${scanMessage.startsWith('Scan failed') ? 'text-red-300 bg-red-900/20' : 'text-green-300 bg-green-900/20'}`}>
            {scanMessage}
          </div>
        )}

        {/* File meta */}
        {content && !loading && (
          <div className="px-5 py-2 border-b border-gray-700 flex-shrink-0 flex flex-wrap gap-4 text-xs text-gray-400">
            <span>Last modified: <span className="text-gray-300">{formatDate(content.lastModified)}</span></span>
            <span>Size: <span className="text-gray-300">{formatSize(content.sizeBytes)}</span></span>
            <span className="font-mono text-gray-500 truncate max-w-xs" title={content.path}>{content.path}</span>
          </div>
        )}

        {/* Content area */}
        <div className="flex-1 overflow-auto p-5 min-h-0">
          {loading && (
            <div className="flex items-center gap-2 text-sm text-gray-400">
              <span className="inline-block w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
              Loading roadmap...
            </div>
          )}
          {error && !loading && (
            <div className="text-sm text-red-400 bg-red-900/20 border border-red-700/50 rounded px-4 py-3">
              {error}
            </div>
          )}
          {content && !loading && (
            <pre className="font-mono text-xs text-gray-200 whitespace-pre-wrap break-words leading-relaxed">
              {content.content}
            </pre>
          )}
          {!content && !loading && !error && (
            <div className="text-sm text-gray-500">No roadmap selected.</div>
          )}
        </div>
      </div>
    </div>
  );
};

export default RoadmapViewerModal;
