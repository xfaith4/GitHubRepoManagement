import React, { useState, useCallback } from 'react';
import type { RepoEvaluationResult, EvaluationFinding, EvaluationFindingSeverity, EvaluationFindingCategory } from '../types';
import { evaluateRepo, createRepoRoadmap } from '../services/apiClient';
import { SpinnerIcon } from './icons';

interface Props {
  repoName: string;
  localPath?: string;
  onClose: () => void;
  onRoadmapCreated?: () => void;
}

const SEVERITY_ORDER: EvaluationFindingSeverity[] = ['critical', 'high', 'medium', 'low'];

const SEVERITY_BADGE: Record<EvaluationFindingSeverity, string> = {
  critical: 'bg-red-600 text-white',
  high:     'bg-orange-500 text-white',
  medium:   'bg-yellow-500 text-black',
  low:      'bg-gray-600 text-gray-200',
};

const CATEGORY_LABEL: Record<EvaluationFindingCategory, string> = {
  hardening:     'Hardening',
  documentation: 'Docs',
  ci:            'CI/CD',
  testing:       'Testing',
  security:      'Security',
  compliance:    'Compliance',
};

const CATEGORY_COLOR: Record<EvaluationFindingCategory, string> = {
  hardening:     'text-blue-300',
  documentation: 'text-purple-300',
  ci:            'text-teal-300',
  testing:       'text-green-300',
  security:      'text-red-300',
  compliance:    'text-yellow-300',
};

function FindingRow({ finding }: { finding: EvaluationFinding }) {
  const [expanded, setExpanded] = useState(false);
  return (
    <div className="border border-gray-700 rounded mb-2 overflow-hidden">
      <button
        className="w-full text-left px-3 py-2 flex items-center gap-2 hover:bg-gray-750 transition-colors"
        onClick={() => setExpanded(e => !e)}
      >
        <span className={`text-xs font-mono px-1.5 py-0.5 rounded uppercase ${SEVERITY_BADGE[finding.severity]}`}>
          {finding.severity}
        </span>
        <span className={`text-xs font-medium ${CATEGORY_COLOR[finding.category]}`}>
          {CATEGORY_LABEL[finding.category]}
        </span>
        <span className="text-sm text-gray-200 flex-1">{finding.title}</span>
        <span className="text-gray-500 text-xs">{expanded ? '▲' : '▼'}</span>
      </button>
      {expanded && (
        <div className="px-3 pb-3 pt-1 bg-gray-800 border-t border-gray-700 space-y-2">
          <p className="text-xs text-gray-400">{finding.description}</p>
          <div className="bg-gray-900 rounded px-2 py-1.5">
            <span className="text-xs text-gray-500">Suggested roadmap item: </span>
            <span className="text-xs text-gray-300 font-mono">{finding.roadmapItem}</span>
          </div>
        </div>
      )}
    </div>
  );
}

export const RepoEvaluationModal: React.FC<Props> = ({ repoName, localPath, onClose, onRoadmapCreated }) => {
  const [phase, setPhase] = useState<'idle' | 'evaluating' | 'done' | 'creating' | 'created' | 'error'>('idle');
  const [result, setResult] = useState<RepoEvaluationResult | null>(null);
  const [errorMsg, setErrorMsg] = useState('');
  const [roadmapContent, setRoadmapContent] = useState('');
  const [createError, setCreateError] = useState('');

  const runEvaluation = useCallback(async () => {
    setPhase('evaluating');
    setErrorMsg('');
    try {
      const r = await evaluateRepo(repoName, localPath);
      setResult(r);
      if (!r.hasExistingRoadmap && r.suggestedRoadmapContent) {
        setRoadmapContent(r.suggestedRoadmapContent);
      }
      setPhase('done');
    } catch (e: any) {
      setErrorMsg(e?.message ?? 'Evaluation failed');
      setPhase('error');
    }
  }, [repoName, localPath]);

  const handleCreateRoadmap = useCallback(async () => {
    if (!result) return;
    setPhase('creating');
    setCreateError('');
    try {
      await createRepoRoadmap(repoName, roadmapContent, result.localPath);
      setPhase('created');
      onRoadmapCreated?.();
    } catch (e: any) {
      setCreateError(e?.message ?? 'Failed to create roadmap');
      setPhase('done');
    }
  }, [repoName, roadmapContent, result, onRoadmapCreated]);

  const sortedFindings = result
    ? [...result.findings].sort((a, b) => SEVERITY_ORDER.indexOf(a.severity) - SEVERITY_ORDER.indexOf(b.severity))
    : [];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-gray-850 border border-gray-700 rounded-xl shadow-2xl w-full max-w-2xl max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-700">
          <div>
            <h2 className="text-base font-semibold text-white">Repo Evaluation</h2>
            <p className="text-xs text-gray-400 mt-0.5">{repoName}</p>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-white text-xl leading-none">&times;</button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4">

          {phase === 'idle' && (
            <div className="text-center py-10 space-y-3">
              <p className="text-gray-300 text-sm">
                Analyse <span className="font-semibold text-white">{repoName}</span>'s structure and receive targeted
                hardening suggestions and a ready-to-use ROADMAP.md draft.
              </p>
              <button
                onClick={runEvaluation}
                className="px-5 py-2 bg-indigo-600 hover:bg-indigo-500 text-white text-sm rounded-lg font-medium transition-colors"
              >
                Run Evaluation
              </button>
            </div>
          )}

          {phase === 'evaluating' && (
            <div className="flex flex-col items-center justify-center py-12 gap-3">
              <SpinnerIcon className="w-7 h-7 text-indigo-400 animate-spin" />
              <p className="text-gray-400 text-sm">Evaluating repository structure…</p>
            </div>
          )}

          {phase === 'error' && (
            <div className="bg-red-950 border border-red-700 rounded-lg px-4 py-3 text-sm text-red-300">
              {errorMsg}
              <button onClick={runEvaluation} className="ml-3 underline text-red-200 hover:text-white">Retry</button>
            </div>
          )}

          {(phase === 'done' || phase === 'creating' || phase === 'created') && result && (
            <>
              {/* Summary strip */}
              <div className="flex gap-3 flex-wrap">
                <span className="bg-gray-800 border border-gray-700 rounded px-3 py-1 text-xs text-gray-300">
                  Type: <span className="text-white font-medium">{result.repoType}</span>
                </span>
                <span className="bg-gray-800 border border-gray-700 rounded px-3 py-1 text-xs text-gray-300">
                  Findings: <span className="text-white font-medium">{result.findingCount}</span>
                </span>
                {result.highCount > 0 && (
                  <span className="bg-orange-900/40 border border-orange-700 rounded px-3 py-1 text-xs text-orange-300">
                    {result.highCount} high
                  </span>
                )}
                {result.criticalCount > 0 && (
                  <span className="bg-red-900/40 border border-red-700 rounded px-3 py-1 text-xs text-red-300">
                    {result.criticalCount} critical
                  </span>
                )}
                <span className={`border rounded px-3 py-1 text-xs ${result.hasExistingRoadmap ? 'bg-green-900/30 border-green-700 text-green-300' : 'bg-yellow-900/30 border-yellow-700 text-yellow-300'}`}>
                  {result.hasExistingRoadmap ? 'Roadmap exists' : 'No roadmap'}
                </span>
              </div>

              {createError && (
                <div className="bg-red-950 border border-red-700 rounded px-3 py-2 text-xs text-red-300">{createError}</div>
              )}

              {/* Findings list */}
              {sortedFindings.length > 0 ? (
                <div>
                  <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">Findings</h3>
                  {sortedFindings.map(f => <FindingRow key={f.findingId} finding={f} />)}
                </div>
              ) : (
                <p className="text-sm text-green-400">No issues found — this repository looks well-structured.</p>
              )}

              {/* No existing roadmap: editable draft */}
              {!result.hasExistingRoadmap && phase !== 'created' && (
                <div className="space-y-2">
                  <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Suggested ROADMAP.md</h3>
                  <p className="text-xs text-gray-500">Review and edit the generated content before creating the file.</p>
                  <textarea
                    className="w-full h-56 bg-gray-900 border border-gray-600 rounded-lg p-3 text-xs text-gray-300 font-mono resize-y focus:outline-none focus:border-indigo-500"
                    value={roadmapContent}
                    onChange={e => setRoadmapContent(e.target.value)}
                    spellCheck={false}
                  />
                  <div className="flex justify-end">
                    <button
                      onClick={handleCreateRoadmap}
                      disabled={phase === 'creating' || !roadmapContent.trim()}
                      className="px-4 py-2 bg-green-700 hover:bg-green-600 disabled:bg-gray-700 disabled:text-gray-500 text-white text-sm rounded-lg font-medium transition-colors flex items-center gap-2"
                    >
                      {phase === 'creating' && <SpinnerIcon className="w-4 h-4 animate-spin" />}
                      Create ROADMAP.md
                    </button>
                  </div>
                </div>
              )}

              {/* Existing roadmap: suggested additions */}
              {result.hasExistingRoadmap && result.suggestedAdditions.length > 0 && (
                <div className="space-y-2">
                  <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Suggested Additions to Roadmap</h3>
                  <p className="text-xs text-gray-500">
                    Copy these items into your ROADMAP.md or use the Repair tool to apply them.
                  </p>
                  <div className="bg-gray-900 border border-gray-700 rounded-lg p-3 space-y-1 font-mono text-xs text-gray-300">
                    {result.suggestedAdditions.map((a, i) => (
                      <div key={i} className="flex items-start gap-2">
                        <span className={`mt-0.5 flex-shrink-0 text-xs px-1 rounded ${SEVERITY_BADGE[a.severity]}`}>{a.severity}</span>
                        <span>- [ ] {a.roadmapItem}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {result.hasExistingRoadmap && result.suggestedAdditions.length === 0 && sortedFindings.length === 0 && (
                <p className="text-xs text-green-400">Your roadmap appears up-to-date with no additional suggestions.</p>
              )}
            </>
          )}

          {phase === 'created' && (
            <div className="bg-green-950 border border-green-700 rounded-lg px-4 py-3 text-sm text-green-300">
              ROADMAP.md created successfully in <span className="font-mono text-green-200">{repoName}</span>.
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-5 py-3 border-t border-gray-700 flex justify-end">
          <button
            onClick={onClose}
            className="px-4 py-1.5 text-sm text-gray-300 hover:text-white border border-gray-600 hover:border-gray-400 rounded-lg transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
};

export default RepoEvaluationModal;
