import React from 'react';
import {
  type LeverageMetric,
  type PortfolioLeverage,
  formatLeverageValue,
  measuredMetrics,
  unmeasuredMetrics,
} from '../lib/portfolioLeverage';

// Release 3.6 milestone 5 — does this product return more time than it takes?
//
// Two halves, deliberately. What the product measured, each figure carrying the
// basis that produced it; and what the product does NOT capture, named rather
// than omitted. A panel that quietly dropped the second half would let a
// reader mistake "we never measured this" for "there is nothing here".

function MetricTile({ metric }: { metric: LeverageMetric }) {
  return (
    <div className="bg-gray-800/60 border border-gray-700 rounded-lg px-3 py-2.5">
      <p className="text-[11px] text-gray-400 uppercase tracking-wide">{metric.label}</p>
      <p className="text-xl text-white font-semibold mt-0.5 tabular-nums">{formatLeverageValue(metric)}</p>
      <p className="text-[11px] text-gray-500 mt-1 leading-relaxed">{metric.basis}</p>
      {metric.sampleSize > 0 && (
        <p className="text-[10px] text-gray-600 mt-0.5">n = {metric.sampleSize}</p>
      )}
    </div>
  );
}

export interface LeveragePanelProps {
  leverage: PortfolioLeverage | null | undefined;
}

export const LeveragePanel: React.FC<LeveragePanelProps> = ({ leverage }) => {
  if (!leverage) {
    return (
      <section aria-label="Leverage" className="space-y-2">
        <h3 className="text-sm font-semibold text-gray-200">Leverage</h3>
        <p data-testid="leverage-absent" className="text-xs text-gray-500">
          Leverage was not computed for this window. It is derived from the agent-run, execution, and verification
          ledgers — none of which were readable here.
        </p>
      </section>
    );
  }

  const measured = measuredMetrics(leverage);
  const unmeasured = unmeasuredMetrics(leverage);

  return (
    <section aria-label="Leverage" className="space-y-3">
      <div>
        <h3 className="text-sm font-semibold text-gray-200">Leverage</h3>
        <p className="text-xs text-gray-500 mt-0.5">
          Whether this product returns more time than it takes, over the last {leverage.windowDays} days. Every figure
          names the ledger it came from.
        </p>
      </div>

      {measured.length > 0 && (
        <div data-testid="leverage-measured" className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {measured.map(metric => (
            <MetricTile key={metric.key} metric={metric} />
          ))}
        </div>
      )}

      {unmeasured.length > 0 && (
        <div data-testid="leverage-unmeasured" className="border border-gray-700/70 border-dashed rounded-lg px-3 py-2.5 space-y-1.5">
          <p className="text-[11px] text-gray-400 uppercase tracking-wide">Not captured yet</p>
          <p className="text-[11px] text-gray-500">
            Named here rather than left out — an absent measurement is a gap in the product, not evidence of nothing.
          </p>
          <ul className="space-y-1 pt-0.5">
            {unmeasured.map(metric => (
              <li key={metric.key} className="text-xs text-gray-400">
                <span className="text-gray-300">{metric.label}</span>
                <span className="text-gray-600"> — </span>
                <span className="text-gray-500">{metric.basis}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
};

export default LeveragePanel;
