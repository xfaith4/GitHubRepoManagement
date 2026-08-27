import { describe, it, expect } from 'vitest';
import {
  formatLeverageValue,
  measuredMetrics,
  normalizeLeverageMetric,
  normalizePortfolioLeverage,
  unmeasuredMetrics,
} from './portfolioLeverage';

const metric = (over: Record<string, unknown> = {}) => ({
  key: 'agentFirstPassSuccess',
  label: 'Agent first-pass success',
  value: 50,
  unit: 'percent',
  available: true,
  basis: '1 of 2 completed agent run(s) needed no retry.',
  sampleSize: 2,
  ...over,
});

describe('normalizeLeverageMetric — an unmeasured figure is never a number', () => {
  it('keeps a derived metric intact, basis included', () => {
    const m = normalizeLeverageMetric(metric())!;
    expect(m.value).toBe(50);
    expect(m.available).toBe(true);
    expect(m.basis).toContain('needed no retry');
    expect(m.sampleSize).toBe(2);
  });

  it('strips a value from a metric the backend marked unavailable', () => {
    const m = normalizeLeverageMetric(metric({ available: false, value: 0 }))!;
    expect(m.value).toBeNull();
    expect(m.available).toBe(false);
  });

  it('treats a null value as unavailable even when the flag says otherwise', () => {
    const m = normalizeLeverageMetric(metric({ available: true, value: null }))!;
    expect(m.available).toBe(false);
    expect(m.value).toBeNull();
  });

  it('refuses a metric with no key rather than rendering a nameless tile', () => {
    expect(normalizeLeverageMetric({ label: 'x', value: 1 })).toBeNull();
    expect(normalizeLeverageMetric(null)).toBeNull();
  });
});

describe('formatLeverageValue — the em dash is the point', () => {
  it('shows an em dash for anything unmeasured, never a zero', () => {
    expect(formatLeverageValue(normalizeLeverageMetric(metric({ available: false, value: 0 }))!)).toBe('—');
    expect(formatLeverageValue(normalizeLeverageMetric(metric({ available: false, value: null }))!)).toBe('—');
  });

  it('formats each unit in the reader\'s terms', () => {
    expect(formatLeverageValue(normalizeLeverageMetric(metric({ value: 62.53 }))!)).toBe('62.5%');
    expect(formatLeverageValue(normalizeLeverageMetric(metric({ unit: 'count', value: 4 }))!)).toBe('4');
    expect(formatLeverageValue(normalizeLeverageMetric(metric({ unit: 'minutes', value: 45 }))!)).toBe('45 min');
    expect(formatLeverageValue(normalizeLeverageMetric(metric({ unit: 'minutes', value: 150 }))!)).toBe('2.5 h');
  });
});

describe('normalizePortfolioLeverage', () => {
  const payload = {
    schemaVersion: 'v1',
    windowDays: 30,
    metricCount: 3,
    availableCount: 99,
    metrics: [
      metric(),
      metric({ key: 'operatorMinutesPerTask', label: 'Operator minutes per task', unit: 'minutes', value: null, available: false, basis: 'Not captured: the product records agent elapsed time, never the operator\'s own minutes.' }),
      metric({ key: 'recommendationsAccepted', label: 'Recommendations accepted', value: null, available: false, basis: 'Not captured: approving a packaged item leaves no accept/reject ledger.' }),
      { label: 'no key' },
    ],
  };

  it('recounts availability from the metrics rather than trusting the header', () => {
    const l = normalizePortfolioLeverage(payload)!;
    expect(l.metrics).toHaveLength(3);
    expect(l.availableCount).toBe(1);
    expect(l.windowDays).toBe(30);
  });

  it('separates what was measured from what the product admits it does not capture', () => {
    const l = normalizePortfolioLeverage(payload);
    expect(measuredMetrics(l).map(m => m.key)).toEqual(['agentFirstPassSuccess']);
    const unmeasured = unmeasuredMetrics(l);
    expect(unmeasured.map(m => m.key)).toEqual(['operatorMinutesPerTask', 'recommendationsAccepted']);
    // Each one must still say why — that is what makes the gap actionable.
    for (const m of unmeasured) expect(m.basis).toMatch(/Not captured/);
  });

  it('reads an absent payload as absent, not as an empty scorecard', () => {
    expect(normalizePortfolioLeverage(null)).toBeNull();
    expect(normalizePortfolioLeverage({ metrics: [] })).toBeNull();
    expect(measuredMetrics(null)).toEqual([]);
    expect(unmeasuredMetrics(null)).toEqual([]);
  });
});
