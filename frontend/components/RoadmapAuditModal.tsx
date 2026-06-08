import React, { useState, useEffect } from 'react';
import { type RoadmapAuditEntry, type RoadmapAuditFinding, type RoadmapMaturityLevel } from '../types';
import { getRoadmapAudit } from '../services/apiClient';
import { SpinnerIcon } from './icons';

interface RoadmapAuditModalProps {
  isOpen: boolean;
  repoName: string | null;
  onClose: () => void;
}

const MATURITY_CONFIG: Record<RoadmapMaturityLevel, { label: string; badgeClass: string; dotClass: string; description: string }> = {
  'L0-Absent': {
    label: 'L0 — Absent',
    badgeClass: 'bg-gray-800 text-gray-400 border-gray-600',
    dotClass: 'bg-gray-500',
    description: 'No roadmap file present.',
  },
  'L1-Informal': {
    label: 'L1 — Informal',
    badgeClass: 'bg-red-900/50 text-red-300 border-red-700/50',
    dotClass: 'bg-red-400',
    description: 'Roadmap exists but is a flat list, lacks structure, or has parse errors.',
  },
  'L2-Structured': {
    label: 'L2 — Structured',
    badgeClass: 'bg-orange-900/50 text-orange-300 border-orange-700/50',
    dotClass: 'bg-orange-400',
    description: 'Roadmap has checkboxes and some organization, but lacks release sections or acceptance criteria.',
  },
  'L3-Contract-Ready': {
    label: 'L3 — Contract-Ready',
    badgeClass: 'bg-yellow-900/50 text-yellow-300 border-yellow-700/50',
    dotClass: 'bg-yellow-400',
    description: 'Roadmap uses release sections, has acceptance criteria, and is parseable.',
  },
  'L4-Orchestration-Ready': {
    label: 'L4 — Orchestration-Ready',
    badgeClass: 'bg-green-900/50 text-green-300 border-green-700/50',
    dotClass: 'bg-green-400',
    description: 'Roadmap passes all critical and warning rules. Suitable for Copilot orchestration.',
  },
};

const SEVERITY_COLORS: Record<string, string> = {
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
  const config = MATURITY_CONFIG[level] ?? MATURITY_CONFIG['L0-Absent'];
  return (
    <span className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded border text-xs font-medium ${config.badgeClass}`}>
      <span className={`inline-block w-1.5 h-1.5 rounded-full ${config.dotClass}`} />
      {config.label}
    </span>
  );
}

function ScoreBar({ score }: { score: number }) {
  const pct = Math.max(0, Math.min(100, score));
  const colorClass =
    pct >= 85 ? 'bg-green-500' :
    pct >= 65 ? 'bg-yellow-500' :
    pct >= 40 ? 'bg-orange-500' :
    'bg-red-500';
  return (
    <div className="flex items-center gap-2">
      <div className="flex-1 bg-gray-700 rounded-full h-2">
        <div className={`h-2 rounded-full transition-all ${colorClass}`} style={{ width: `${pct}%` }} />
      </div>
      <span className="text-xs text-gray-300 font-mono w-8 text-right">{pct}</span>
    </div>
  );
}

function FindingRow({ finding }: { finding: RoadmapAuditFinding }) {
  const [expanded, setExpanded] = useState(false);
  return (
    <div className={`rounded border px-3 py-2 text-sm ${SEVERITY_BG[finding.severity] ?? SEVERITY_BG.info}`}>
      <div
        className="flex items-start gap-2 cursor-pointer"
        onClick={() => setExpanded(v => !v)}
        role="button"
        aria-expanded={expanded}
      >
        <span className={`mt-0.5 font-medium text-xs uppercase tracking-wide ${SEVERITY_COLORS[finding.severity] ?? ''}`}>
          {finding.severity}
        </span>
        <span className="flex-1 text-gray-200">{finding.message}</span>
        {finding.recommendedAction && (
          <span className="text-gray-500 text-xs ml-1">{expanded ? '▲' : '▼'}</span>
        )}
      </div>
      {expanded && finding.recommendedAction && (
        <p className="mt-1.5 text-xs text-gray-400 pl-14">{finding.recommendedAction}</p>
      )}
    </div>
  );
}

function ContractDetail({ entry }: { entry: RoadmapAuditEntry }) {
  const maturityConfig = MATURITY_CONFIG[entry.maturityLevel] ?? MATURITY_CONFIG['L0-Absent'];
  const findings = entry.auditFindings ?? [];
  const critCount = findings.filter(f => f.severity === 'critical').length;
  const warnCount = findings.filter(f => f.severity === 'warning').length;
  const infoCount = findings.filter(f => f.severity === 'info').length;

  return (
    <div className="space-y-4">
      {/* Score & Level */}
      <div className="bg-gray-800/60 rounded-lg border border-gray-700/50 p-4 space-y-3">
        <div className="flex items-center justify-between">
          <span className="text-sm font-medium text-gray-300">Maturity Level</span>
          <MaturityBadge level={entry.maturityLevel} />
        </div>
        <div>
          <div className="flex items-center justify-between mb-1">
            <span className="text-sm font-medium text-gray-300">Contract Score</span>
            <span className="text-xs text-gray-400">{entry.maturityScore} / 100</span>
          </div>
          <ScoreBar score={entry.maturityScore} />
        </div>
        <p className="text-xs text-gray-400 italic">{maturityConfig.description}</p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-2">
        {[
          { label: 'Pending Items', value: entry.pendingCount, color: 'text-yellow-400' },
          { label: 'Completed Items', value: entry.completedCount, color: 'text-green-400' },
          { label: 'Release Sections', value: entry.releaseCount ?? 0, color: 'text-blue-400' },
        ].map(({ label, value, color }) => (
          <div key={label} className="bg-gray-800/60 rounded border border-gray-700/50 p-2 text-center">
            <div className={`text-lg font-bold ${color}`}>{value}</div>
            <div className="text-xs text-gray-500">{label}</div>
          </div>
        ))}
      </div>

      {/* Structural Flags */}
      <div className="bg-gray-800/60 rounded-lg border border-gray-700/50 p-3">
        <p className="text-xs font-medium text-gray-400 uppercase tracking-wide mb-2">Contract Structure</p>
        <div className="grid grid-cols-2 gap-1.5">
          {[
            { label: 'Product Intent', value: entry.hasProductIntent },
            { label: 'Release Sections', value: entry.hasReleaseSections },
            { label: 'Acceptance Criteria', value: entry.hasAcceptanceCriteria },
            { label: 'Out-of-Scope Boundaries', value: entry.hasOutOfScope },
          ].map(({ label, value }) => (
            <div key={label} className="flex items-center gap-1.5 text-xs">
              <span className={value ? 'text-green-400' : 'text-gray-600'}>{value ? '✓' : '✗'}</span>
              <span className={value ? 'text-gray-300' : 'text-gray-500'}>{label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Audit Findings */}
      {findings.length > 0 && (
        <div>
          <div className="flex items-center gap-2 mb-2">
            <p className="text-xs font-medium text-gray-400 uppercase tracking-wide">Audit Findings</p>
            <div className="flex gap-1.5 text-xs">
              {critCount > 0 && <span className="text-red-400">{critCount} critical</span>}
              {warnCount > 0 && <span className="text-yellow-400">{warnCount} warning</span>}
              {infoCount > 0 && <span className="text-blue-400">{infoCount} info</span>}
            </div>
          </div>
          <div className="space-y-1.5">
            {findings.map((f, i) => <FindingRow key={f.ruleId ?? i} finding={f} />)}
          </div>
        </div>
      )}

      {findings.length === 0 && entry.maturityLevel === 'L4-Orchestration-Ready' && (
        <div className="rounded border border-green-700/40 bg-green-900/20 px-3 py-2 text-sm text-green-300">
          ✓ No audit findings. This roadmap passes all contract rules.
        </div>
      )}

      {/* Parse error */}
      {entry.parseError && (
        <div className="rounded border border-red-700/40 bg-red-900/20 px-3 py-2 text-xs text-red-300">
          Parse error: {entry.parseError}
        </div>
      )}
    </div>
  );
}

const RoadmapAuditModal: React.FC<RoadmapAuditModalProps> = ({ isOpen, repoName, onClose }) => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [entry, setEntry] = useState<RoadmapAuditEntry | null>(null);

  useEffect(() => {
    if (!isOpen || !repoName) {
      setEntry(null);
      setError(null);
      return;
    }
    let cancelled = false;
    setLoading(true);
    setError(null);

    getRoadmapAudit()
      .then(index => {
        if (cancelled) return;
        const found = index.entries.find(e => e.repoName === repoName) ?? null;
        setEntry(found);
        if (!found) {
          setError(`No audit data found for "${repoName}". Run a roadmap audit scan first.`);
        }
      })
      .catch(err => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : 'Failed to load roadmap audit data.');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => { cancelled = true; };
  }, [isOpen, repoName]);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-4"
      onClick={e => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-full max-w-lg max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-3.5 border-b border-gray-700/60">
          <div>
            <h2 className="text-base font-semibold text-white">Roadmap Contract Audit</h2>
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

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-5 py-4">
          {loading && (
            <div className="flex items-center justify-center py-12 gap-3 text-gray-400">
              <SpinnerIcon className="w-5 h-5 animate-spin" />
              <span className="text-sm">Loading audit data…</span>
            </div>
          )}
          {!loading && error && (
            <div className="rounded border border-red-700/40 bg-red-900/20 px-4 py-3 text-sm text-red-300">
              {error}
            </div>
          )}
          {!loading && !error && entry && <ContractDetail entry={entry} />}
        </div>

        {/* Footer */}
        <div className="px-5 py-3 border-t border-gray-700/60 flex justify-end">
          <button
            onClick={onClose}
            className="px-4 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-sm text-gray-200 transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
};

export default RoadmapAuditModal;
