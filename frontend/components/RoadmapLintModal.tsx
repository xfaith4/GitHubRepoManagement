import React, { useState, useEffect, useCallback } from 'react';
import type { RoadmapLintResult, RoadmapLintFinding } from '../types';
import { getRoadmapLint } from '../services/apiClient';

interface RoadmapLintModalProps {
  repoName: string;
  onClose: () => void;
}

const severityOrder: Record<string, number> = { error: 0, warning: 1, info: 2 };

const severityBadge = (severity: string) => {
  if (severity === 'error') return 'bg-red-100 text-red-700 border border-red-200';
  if (severity === 'warning') return 'bg-yellow-100 text-yellow-700 border border-yellow-200';
  return 'bg-blue-50 text-blue-600 border border-blue-200';
};

const FindingRow: React.FC<{ finding: RoadmapLintFinding }> = ({ finding }) => {
  const [expanded, setExpanded] = useState(false);
  return (
    <div className="border border-gray-200 rounded overflow-hidden">
      <button
        onClick={() => setExpanded(prev => !prev)}
        className="w-full flex items-center gap-3 p-3 text-left hover:bg-gray-50"
      >
        <span className={`px-2 py-0.5 rounded text-xs font-semibold ${severityBadge(finding.severity)}`}>
          {finding.severity}
        </span>
        <span className="text-xs text-gray-400 font-mono">{finding.ruleId}</span>
        <span className="flex-1 text-sm text-gray-700">{finding.message}</span>
        {finding.line != null && (
          <span className="text-xs text-gray-400">line {finding.line}</span>
        )}
        <span className="text-gray-400 text-xs">{expanded ? '▲' : '▼'}</span>
      </button>
      {expanded && finding.recommendedAction && (
        <div className="px-4 pb-3 text-sm text-gray-600 border-t border-gray-100 pt-2 bg-gray-50">
          <span className="font-semibold text-gray-500">Recommended: </span>
          {finding.recommendedAction}
        </div>
      )}
    </div>
  );
};

export const RoadmapLintModal: React.FC<RoadmapLintModalProps> = ({ repoName, onClose }) => {
  const [result, setResult] = useState<RoadmapLintResult | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const data = await getRoadmapLint(repoName);
      setResult(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Lint request failed');
    } finally {
      setIsLoading(false);
    }
  }, [repoName]);

  useEffect(() => { load(); }, [load]);

  const sortedFindings = result?.findings
    ? [...result.findings].sort((a, b) => (severityOrder[a.severity] ?? 9) - (severityOrder[b.severity] ?? 9))
    : [];

  const errorCount = sortedFindings.filter(f => f.severity === 'error').length;
  const warnCount = sortedFindings.filter(f => f.severity === 'warning').length;
  const infoCount = sortedFindings.filter(f => f.severity === 'info').length;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-2xl max-h-[85vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200">
          <div>
            <h2 className="text-lg font-semibold text-gray-900">Roadmap Lint</h2>
            <p className="text-sm text-gray-500 mt-0.5">{repoName}</p>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-2xl leading-none">&times;</button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-4">
          {isLoading && (
            <div className="flex items-center justify-center py-12 text-gray-500">Running lint checks...</div>
          )}

          {error && (
            <div className="bg-red-50 border border-red-200 rounded p-4 text-red-700 text-sm">{error}</div>
          )}

          {!isLoading && result && (
            <>
              {/* Summary bar */}
              <div className="flex items-center gap-4">
                <span className={`px-3 py-1.5 rounded-full text-sm font-semibold ${
                  result.lintPassed ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'
                }`}>
                  {result.lintPassed ? '✓ Lint Passed' : '✗ Lint Failed'}
                </span>
                {errorCount > 0 && (
                  <span className="text-sm text-red-600">{errorCount} error{errorCount !== 1 ? 's' : ''}</span>
                )}
                {warnCount > 0 && (
                  <span className="text-sm text-yellow-600">{warnCount} warning{warnCount !== 1 ? 's' : ''}</span>
                )}
                {infoCount > 0 && (
                  <span className="text-sm text-blue-500">{infoCount} info</span>
                )}
              </div>

              <p className="text-sm text-gray-500">{result.summary}</p>

              {sortedFindings.length === 0 ? (
                <div className="bg-green-50 border border-green-200 rounded p-4 text-green-700 text-sm">
                  No lint findings — roadmap passes all checks.
                </div>
              ) : (
                <div className="space-y-2">
                  <h3 className="text-sm font-semibold text-gray-600">Findings</h3>
                  {sortedFindings.map((f, i) => (
                    <FindingRow key={i} finding={f} />
                  ))}
                </div>
              )}

              <p className="text-xs text-gray-400">Linted at {new Date(result.lintedAt).toLocaleString()}</p>
            </>
          )}
        </div>

        <div className="px-6 py-4 border-t border-gray-200 flex justify-end">
          <button onClick={onClose} className="px-4 py-2 bg-gray-100 text-gray-700 text-sm rounded hover:bg-gray-200">
            Close
          </button>
        </div>
      </div>
    </div>
  );
};
