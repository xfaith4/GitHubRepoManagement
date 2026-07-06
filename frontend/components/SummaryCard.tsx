
import React from 'react';

interface SummaryCardProps {
  title: string;
  value: number | string;
  color: 'blue' | 'green' | 'yellow' | 'red' | 'purple' | 'orange';
  icon?: React.ReactNode;
  // Optional in-app definition of what this metric counts. Surfaced as an
  // always-available hover/focus tooltip plus a small "?" affordance so the
  // number's meaning is discoverable without leaving the card (Release 2.6).
  tooltip?: string;
}

const colorClasses = {
  blue: 'border-blue-500/50',
  green: 'border-green-500/50',
  yellow: 'border-yellow-500/50',
  red: 'border-red-500/50',
  purple: 'border-purple-500/50',
  orange: 'border-orange-500/50',
};

const SummaryCard: React.FC<SummaryCardProps> = ({ title, value, color, icon, tooltip }) => {
  const testId = `summary-${title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')}`;
  return (
    <div
      data-testid={testId}
      className={`bg-gray-800 p-5 rounded-lg shadow-md border-l-4 ${colorClasses[color]}`}
      title={tooltip}
    >
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-gray-400 flex items-center gap-1.5">
          {title}
          {tooltip && (
            <span
              className="inline-flex items-center justify-center w-4 h-4 rounded-full bg-gray-700 text-gray-300 text-[10px] font-bold cursor-help select-none"
              tabIndex={0}
              role="img"
              aria-label={`${title} — ${tooltip}`}
              title={tooltip}
            >
              ?
            </span>
          )}
        </h3>
        {icon && <div className="text-gray-500">{icon}</div>}
      </div>
      <p className="mt-2 text-3xl font-semibold text-gray-100">{value}</p>
    </div>
  );
};

export default SummaryCard;
