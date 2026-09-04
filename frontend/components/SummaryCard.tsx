
import React from 'react';

interface SummaryCardProps {
  title: string;
  /**
   * `null` means NOT MEASURABLE from the current data source, which is not the
   * same as zero. A count the source cannot observe must never be painted as a
   * number: in GitHub mode `Dirty Repositories` read `0`, and `0` says "nothing
   * is dirty" when the truth is "there is no working tree here to look at".
   * Pass `unavailableReason` with it so the card can say why.
   */
  value: number | string | null;
  color: 'blue' | 'green' | 'yellow' | 'red' | 'purple' | 'orange';
  icon?: React.ReactNode;
  // Optional in-app definition of what this metric counts. Surfaced as an
  // always-available hover/focus tooltip plus a small "?" affordance so the
  // number's meaning is discoverable without leaving the card (Release 2.6).
  tooltip?: string;
  /** Why this metric is unmeasurable here. Required in spirit when value is null. */
  unavailableReason?: string;
}

const colorClasses = {
  blue: 'border-blue-500/50',
  green: 'border-green-500/50',
  yellow: 'border-yellow-500/50',
  red: 'border-red-500/50',
  purple: 'border-purple-500/50',
  orange: 'border-orange-500/50',
};

const SummaryCard: React.FC<SummaryCardProps> = ({ title, value, color, icon, tooltip, unavailableReason }) => {
  const testId = `summary-${title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')}`;
  const unavailable = value === null;
  // The reason replaces the definition tooltip when there is no number: "what
  // this counts" matters less than "why there is nothing to count".
  const effectiveTooltip = unavailable ? (unavailableReason ?? tooltip) : tooltip;
  return (
    <div
      data-testid={testId}
      data-unavailable={unavailable ? 'true' : undefined}
      className={`bg-gray-800 p-5 rounded-lg shadow-md border-l-4 ${colorClasses[color]}`}
      title={effectiveTooltip}
    >
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-gray-400 flex items-center gap-1.5">
          {title}
          {effectiveTooltip && (
            <span
              className="inline-flex items-center justify-center w-4 h-4 rounded-full bg-gray-700 text-gray-300 text-[10px] font-bold cursor-help select-none"
              tabIndex={0}
              role="img"
              aria-label={`${title} — ${effectiveTooltip}`}
              title={effectiveTooltip}
            >
              ?
            </span>
          )}
        </h3>
        {icon && <div className="text-gray-500">{icon}</div>}
      </div>
      {unavailable ? (
        <p className="mt-2 text-3xl font-semibold text-gray-500" aria-label={`${title} — not measurable from this source`}>
          &mdash;
        </p>
      ) : (
        <p className="mt-2 text-3xl font-semibold text-gray-100">{value}</p>
      )}
      {unavailable && unavailableReason && (
        <p className="mt-1 text-sm text-gray-400">{unavailableReason}</p>
      )}
    </div>
  );
};

export default SummaryCard;
