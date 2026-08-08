import React from 'react';
import { resolveProvenance } from '../lib/dataProvenance';

interface ProvenanceNoticeProps {
  /** Repo count from the current scan. */
  liveRepoCount: number;
  /** Entry count in the persisted index backing the figures shown below. */
  persistedEntryCount: number;
  /** ISO timestamp the persisted index was generated, when known. */
  persistedGeneratedAt?: string | null;
  /** Optional test hook / layout override. */
  testId?: string;
  className?: string;
}

/**
 * Renders the carried-over-data warning when a view's figures come from an
 * earlier scan than the header's repo count — the "0 repos but 18 L2 repos in
 * the queue" contradiction. Renders nothing in the 'live' and 'empty' states,
 * so it is safe to mount unconditionally above any index-backed panel.
 */
const ProvenanceNotice: React.FC<ProvenanceNoticeProps> = ({
  liveRepoCount,
  persistedEntryCount,
  persistedGeneratedAt,
  testId = 'provenance-notice',
  className = '',
}) => {
  const provenance = resolveProvenance(
    { liveRepoCount, persistedEntryCount, persistedGeneratedAt },
    iso => new Date(iso).toLocaleString()
  );

  if (!provenance.isMismatch || !provenance.message) {
    return null;
  }

  return (
    <div
      data-testid={testId}
      data-provenance-state={provenance.state}
      role="status"
      className={`flex items-start gap-2 rounded-lg border border-amber-700/50 bg-amber-900/20 px-3 py-2 text-xs text-amber-100 ${className}`}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        className="w-4 h-4 flex-shrink-0 mt-0.5"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
        <line x1="12" y1="9" x2="12" y2="13" />
        <line x1="12" y1="17" x2="12.01" y2="17" />
      </svg>
      <span>
        <strong className="font-semibold">Carried-over data. </strong>
        {provenance.message}
      </span>
    </div>
  );
};

export default ProvenanceNotice;
