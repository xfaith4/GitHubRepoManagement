import type { AiDocUsage } from '../types';

/**
 * Presentation rules for AI token usage and cost.
 *
 * The rule this module exists to enforce: a number nobody measured is never
 * rendered as a number. "$0.00" and "unmeasured" are different claims about a
 * run — the first says it was free, and only the second is safe to make by
 * default. `tokenUsage` and `apiSpendUsd` shipped through the agent-run record,
 * `tokens_reported` in app.db and out to analytics while production code never
 * wrote either one; this is the surface that has to stay honest about that.
 */

/** Why a token count is or is not available. */
export const USAGE_SOURCE_LABEL: Record<AiDocUsage['source'], string> = {
  'provider-usage': 'reported by the model',
  'absent': 'the model reported no usage',
  'call-failed': 'the provider call failed',
  'not-applicable': 'no model was called',
};

/** Why a cost is or is not available. Empty string = the cost is real, so no caveat is needed. */
export const COST_BASIS_LABEL: Record<string, string> = {
  'priced-from-settings': '',
  'no-price-configured': 'no price configured for this model',
  'no-model-id': 'the provider reported no model id',
  'price-incomplete': 'the configured price is missing a rate',
  'price-invalid': 'the configured price is not a number',
  'token-detail-insufficient': 'the provider reported a total but no input/output split',
  'usage-absent': 'the model reported no usage',
  'call-failed': 'the provider call failed',
  'not-applicable': 'no model was called',
};

export interface UsageDisplay {
  /** Token text, already formatted — either a count or the word "unmeasured". */
  tokensText: string;
  /** "1,234 in / 567 out", or null when there is no split to show. */
  tokenBreakdown: string | null;
  /** Cost text — either a dollar figure or the word "unmeasured". */
  costText: string;
  /** Why the cost reads the way it does. Null when the figure is real and needs no caveat. */
  costCaveat: string | null;
  /** True when real counts came back from a model. */
  measured: boolean;
  /**
   * True when a model was called and reported nothing. This is a defect rather
   * than a normal state, and a surface may want to say so differently.
   */
  reportingGap: boolean;
}

const UNMEASURED = 'unmeasured';

function formatCount(value: number | null | undefined): string | null {
  if (value === null || value === undefined || !Number.isFinite(value)) return null;
  return value.toLocaleString();
}

/**
 * Turn a usage record into display strings that never overstate what is known.
 *
 * A missing record is not treated as zero usage: it is treated as a model that
 * reported nothing, which is what a consumer written before usage existed would
 * actually have produced.
 */
export function describeUsage(usage: AiDocUsage | null | undefined): UsageDisplay {
  const source: AiDocUsage['source'] = usage?.source ?? 'absent';
  const measured = usage?.measured === true;
  const sourceLabel = USAGE_SOURCE_LABEL[source] ?? USAGE_SOURCE_LABEL.absent;

  const total = formatCount(usage?.totalTokens);
  const input = formatCount(usage?.inputTokens);
  const output = formatCount(usage?.outputTokens);

  // Counts are only shown when the provider actually reported them. A count
  // present on an unmeasured record would be a contradiction; trust `measured`.
  const tokensText = measured && total !== null ? `${total} tokens` : `${UNMEASURED} — ${sourceLabel}`;
  const tokenBreakdown = measured && input !== null && output !== null ? `${input} in / ${output} out` : null;

  const cost = usage?.costUsd;
  const hasCost = measured && cost !== null && cost !== undefined && Number.isFinite(cost);
  const basis = usage?.costBasis ?? 'usage-absent';
  const caveat = COST_BASIS_LABEL[basis] ?? basis;

  return {
    tokensText,
    tokenBreakdown,
    // Four decimals: a single doc rewrite can cost well under a cent, and
    // rounding that to $0.00 would recreate the exact misreading this avoids.
    costText: hasCost ? `$${(cost as number).toFixed(4)}` : UNMEASURED,
    costCaveat: hasCost ? (caveat === '' ? null : caveat) : caveat === '' ? null : caveat,
    measured,
    reportingGap: source === 'absent',
  };
}
