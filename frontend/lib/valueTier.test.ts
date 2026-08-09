import { describe, it, expect } from 'vitest';
import {
  VALUE_TIER_CONFIG,
  VALUE_TIER_ORDER,
  getValueTierPresentation,
  getValueTierRank,
  formatValueScoreLabel,
} from './valueTier';
import { type PortfolioValueTier } from '../types';

// Every tier the API type declares. If PortfolioValueTier gains a member and
// this list is not updated, the `satisfies` check below fails to compile — the
// point being that a new backend tier cannot silently render as a raw slug.
const ALL_TIERS = [
  'highest',
  'high',
  'medium',
  'low',
  'deferred',
  'unscored',
] as const satisfies readonly PortfolioValueTier[];

describe('VALUE_TIER_CONFIG — every declared tier is presentable', () => {
  it('has an entry for every tier the API can return', () => {
    for (const tier of ALL_TIERS) {
      expect(VALUE_TIER_CONFIG[tier], `missing config for tier '${tier}'`).toBeDefined();
    }
    expect(Object.keys(VALUE_TIER_CONFIG).sort()).toEqual([...ALL_TIERS].sort());
  });

  it('gives every tier a non-empty label and both class strings', () => {
    for (const tier of ALL_TIERS) {
      const config = VALUE_TIER_CONFIG[tier];
      expect(config.label.length, `empty label for '${tier}'`).toBeGreaterThan(0);
      expect(config.chipClass.length, `empty chipClass for '${tier}'`).toBeGreaterThan(0);
      expect(config.scoreClass.length, `empty scoreClass for '${tier}'`).toBeGreaterThan(0);
    }
  });

  it('gives each tier a distinct label, so two tiers never read the same', () => {
    const labels = ALL_TIERS.map((tier) => VALUE_TIER_CONFIG[tier].label);
    expect(new Set(labels).size).toBe(labels.length);
  });
});

describe('getValueTierPresentation — degrades instead of returning undefined', () => {
  it('resolves each known tier to its own config', () => {
    for (const tier of ALL_TIERS) {
      expect(getValueTierPresentation(tier)).toBe(VALUE_TIER_CONFIG[tier]);
    }
  });

  it('falls back to Unscored for null and undefined', () => {
    expect(getValueTierPresentation(null).label).toBe('Unscored');
    expect(getValueTierPresentation(undefined).label).toBe('Unscored');
  });

  it('falls back to Unscored for a tier outside the known set', () => {
    // Cast: the scenario under test is precisely a backend value the frontend
    // type does not know about yet.
    expect(getValueTierPresentation('platinum' as PortfolioValueTier).label).toBe('Unscored');
  });
});

describe('getValueTierRank — ranks highest-value first', () => {
  it('orders the tiers highest → deferred', () => {
    const ranked = [...ALL_TIERS].sort((a, b) => getValueTierRank(a) - getValueTierRank(b));
    expect(ranked).toEqual(['highest', 'high', 'medium', 'low', 'deferred', 'unscored']);
  });

  it('ranks highest strictly ahead of every other tier', () => {
    for (const tier of ALL_TIERS.filter((t) => t !== 'highest')) {
      expect(getValueTierRank('highest')).toBeLessThan(getValueTierRank(tier));
    }
  });

  it('sorts an unknown or absent tier last, never ahead of a scored item', () => {
    expect(getValueTierRank(undefined)).toBeGreaterThanOrEqual(VALUE_TIER_ORDER.length);
    expect(getValueTierRank(null)).toBeGreaterThanOrEqual(VALUE_TIER_ORDER.length);
    expect(getValueTierRank('platinum' as PortfolioValueTier)).toBeGreaterThanOrEqual(VALUE_TIER_ORDER.length);
    expect(getValueTierRank('platinum' as PortfolioValueTier)).toBeGreaterThan(getValueTierRank('deferred'));
  });

  it('covers every tier in VALUE_TIER_ORDER exactly once', () => {
    expect([...VALUE_TIER_ORDER].sort()).toEqual([...ALL_TIERS].sort());
  });
});

describe('formatValueScoreLabel — the tooltip score line', () => {
  it('pairs the score with the tier label', () => {
    expect(formatValueScoreLabel(87, 'highest')).toBe('87 (Highest)');
  });

  it('keeps a zero score rather than treating it as missing', () => {
    expect(formatValueScoreLabel(0, 'low')).toBe('0 (Low)');
  });

  it('reports n/a for a null, undefined, or non-finite score', () => {
    expect(formatValueScoreLabel(null, 'medium')).toBe('n/a (Medium)');
    expect(formatValueScoreLabel(undefined, 'medium')).toBe('n/a (Medium)');
    expect(formatValueScoreLabel(Number.NaN, 'medium')).toBe('n/a (Medium)');
  });

  it('uses the Unscored label when the tier is missing', () => {
    expect(formatValueScoreLabel(12, null)).toBe('12 (Unscored)');
  });
});
