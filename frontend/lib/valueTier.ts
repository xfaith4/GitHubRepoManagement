// Value-tier presentation for ranked roadmap items (Release 2.7 Phase D).
//
// The tier is the operator-facing shorthand for `value-scoring.json`'s settled
// semantics (MAX within a dimension + the `effortFit` floor). Extracted from
// WorkQueueView so the mapping is unit-testable: a tier the backend can emit
// but the UI has no entry for would otherwise render as a raw slug, and a
// missing/null tier — which the API returns for an unscored item — must degrade
// to the explicit "Unscored" presentation rather than to an empty chip.

import { type PortfolioValueTier } from '../types';

export interface ValueTierPresentation {
  label: string;
  chipClass: string;
  scoreClass: string;
}

export const VALUE_TIER_CONFIG: Record<PortfolioValueTier, ValueTierPresentation> = {
  highest: {
    label: 'Highest',
    chipClass: 'bg-emerald-900/40 text-emerald-200 border-emerald-700/50',
    scoreClass: 'text-emerald-200',
  },
  high: {
    label: 'High',
    chipClass: 'bg-cyan-900/40 text-cyan-200 border-cyan-700/50',
    scoreClass: 'text-cyan-200',
  },
  medium: {
    label: 'Medium',
    chipClass: 'bg-indigo-900/40 text-indigo-200 border-indigo-700/50',
    scoreClass: 'text-indigo-200',
  },
  low: {
    label: 'Low',
    chipClass: 'bg-slate-800 text-slate-200 border-slate-600',
    scoreClass: 'text-slate-200',
  },
  deferred: {
    label: 'Deferred',
    chipClass: 'bg-amber-900/40 text-amber-200 border-amber-700/50',
    scoreClass: 'text-amber-200',
  },
  unscored: {
    label: 'Unscored',
    chipClass: 'bg-gray-800 text-gray-300 border-gray-600',
    scoreClass: 'text-gray-300',
  },
};

/**
 * Highest-value first. This is the operator's ranking, so it must not depend on
 * the declaration order of VALUE_TIER_CONFIG or on alphabetical accident.
 */
export const VALUE_TIER_ORDER: PortfolioValueTier[] = [
  'highest',
  'high',
  'medium',
  'low',
  'deferred',
  'unscored',
];

/**
 * Resolve a tier to its presentation, degrading to `unscored` for null,
 * undefined, or any value outside the known set. Never returns undefined —
 * callers render the result directly.
 */
export function getValueTierPresentation(tier?: PortfolioValueTier | null): ValueTierPresentation {
  if (!tier) return VALUE_TIER_CONFIG.unscored;
  return VALUE_TIER_CONFIG[tier] ?? VALUE_TIER_CONFIG.unscored;
}

/**
 * Sort rank for a tier: lower sorts first. Unknown tiers sort last rather than
 * ahead of a genuinely scored item.
 */
export function getValueTierRank(tier?: PortfolioValueTier | null): number {
  if (!tier) return VALUE_TIER_ORDER.length;
  const index = VALUE_TIER_ORDER.indexOf(tier);
  return index === -1 ? VALUE_TIER_ORDER.length : index;
}

/**
 * The score line used in the value-rationale tooltip. Kept here so the tier
 * label shown next to a score can never drift from the chip's label.
 */
export function formatValueScoreLabel(score: number | null | undefined, tier?: PortfolioValueTier | null): string {
  const presentation = getValueTierPresentation(tier);
  const displayScore = typeof score === 'number' && Number.isFinite(score) ? score : 'n/a';
  return `${displayScore} (${presentation.label})`;
}
