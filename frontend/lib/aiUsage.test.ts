import { describe, expect, it } from 'vitest';
import { describeUsage } from './aiUsage';
import type { AiDocUsage } from '../types';

function usage(partial: Partial<AiDocUsage>): AiDocUsage {
  return {
    inputTokens: null,
    outputTokens: null,
    totalTokens: null,
    measured: false,
    source: 'absent',
    costUsd: null,
    costBasis: 'usage-absent',
    ...partial,
  };
}

describe('describeUsage', () => {
  it('shows real counts when the model reported them', () => {
    const d = describeUsage(usage({
      inputTokens: 1234,
      outputTokens: 567,
      totalTokens: 1801,
      measured: true,
      source: 'provider-usage',
      costBasis: 'no-price-configured',
    }));
    expect(d.tokensText).toBe('1,801 tokens');
    expect(d.tokenBreakdown).toBe('1,234 in / 567 out');
    expect(d.measured).toBe(true);
  });

  it('renders an unpriced cost as unmeasured, never as zero', () => {
    const d = describeUsage(usage({
      inputTokens: 10,
      outputTokens: 20,
      totalTokens: 30,
      measured: true,
      source: 'provider-usage',
      costUsd: null,
      costBasis: 'no-price-configured',
    }));
    expect(d.costText).toBe('unmeasured');
    expect(d.costText).not.toContain('0.00');
    expect(d.costCaveat).toBe('no price configured for this model');
  });

  it('shows a real cost with enough precision that a sub-cent run is not rounded to nothing', () => {
    const d = describeUsage(usage({
      inputTokens: 1000,
      outputTokens: 2000,
      totalTokens: 3000,
      measured: true,
      source: 'provider-usage',
      costUsd: 0.000123,
      costBasis: 'priced-from-settings',
    }));
    expect(d.costText).toBe('$0.0001');
    expect(d.costText).not.toBe('$0.00');
    expect(d.costCaveat).toBeNull();
  });

  it('says no model was called for the offline heuristic provider', () => {
    const d = describeUsage(usage({ source: 'not-applicable', costBasis: 'not-applicable' }));
    expect(d.tokensText).toBe('unmeasured — no model was called');
    expect(d.costText).toBe('unmeasured');
    expect(d.reportingGap).toBe(false);
  });

  it('flags a model that answered but reported nothing as a reporting gap', () => {
    const d = describeUsage(usage({ source: 'absent', costBasis: 'usage-absent' }));
    expect(d.reportingGap).toBe(true);
    expect(d.tokensText).toContain('the model reported no usage');
  });

  it('does not treat a failed call as a reporting gap', () => {
    const d = describeUsage(usage({ source: 'call-failed', costBasis: 'call-failed' }));
    expect(d.reportingGap).toBe(false);
    expect(d.tokensText).toContain('the provider call failed');
  });

  it('treats a missing usage record as unreported rather than as zero', () => {
    for (const value of [null, undefined]) {
      const d = describeUsage(value);
      expect(d.tokensText).not.toContain('0 tokens');
      expect(d.costText).toBe('unmeasured');
      expect(d.measured).toBe(false);
    }
  });

  it('never invents a total from a one-sided count', () => {
    const d = describeUsage(usage({ inputTokens: 500, measured: false, source: 'absent' }));
    expect(d.tokensText).toContain('unmeasured');
    expect(d.tokenBreakdown).toBeNull();
  });

  it('keeps a genuine zero distinguishable from an unmeasured one', () => {
    const d = describeUsage(usage({
      inputTokens: 0,
      outputTokens: 0,
      totalTokens: 0,
      measured: true,
      source: 'provider-usage',
      costUsd: 0,
      costBasis: 'priced-from-settings',
    }));
    expect(d.tokensText).toBe('0 tokens');
    expect(d.costText).toBe('$0.0000');
    expect(d.measured).toBe(true);
  });
});
