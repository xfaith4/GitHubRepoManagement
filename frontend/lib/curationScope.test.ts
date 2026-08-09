import { describe, it, expect } from 'vitest';
import {
  getCurationBadgeConfig,
  getCurationRank,
  isInAutomationScope,
  matchesCurationFilters,
} from './curationScope';
import { type RepoCurationState } from '../types';

const ALL_STATES = [
  'none',
  'favorite',
  'portfolio-candidate',
  'archived-ignore',
] as const satisfies readonly RepoCurationState[];

describe('getCurationBadgeConfig', () => {
  it('badges each curated state distinctly', () => {
    const labels = (['favorite', 'portfolio-candidate', 'archived-ignore'] as const).map(
      (state) => getCurationBadgeConfig(state)?.label,
    );
    expect(labels).toEqual(['★ Favorite', '◆ Candidate', '⊘ Ignored']);
    expect(new Set(labels).size).toBe(3);
  });

  it('returns no badge for the uncurated baseline', () => {
    expect(getCurationBadgeConfig('none')).toBeNull();
    expect(getCurationBadgeConfig(undefined)).toBeNull();
    expect(getCurationBadgeConfig(null)).toBeNull();
  });

  it('returns no badge for an unknown state rather than a broken chip', () => {
    expect(getCurationBadgeConfig('retired' as RepoCurationState)).toBeNull();
  });
});

describe('getCurationRank — curated first, archived last', () => {
  it('orders favorite → candidate → uncurated → archived', () => {
    const ranked = [...ALL_STATES].sort((a, b) => getCurationRank(a) - getCurationRank(b));
    expect(ranked).toEqual(['favorite', 'portfolio-candidate', 'none', 'archived-ignore']);
  });

  it('ranks an uncurated repo ahead of an archived one', () => {
    // A repo the operator parked must never outrank one they have not triaged.
    expect(getCurationRank('none')).toBeLessThan(getCurationRank('archived-ignore'));
  });

  it('treats undefined, null, and an unknown state as uncurated', () => {
    expect(getCurationRank(undefined)).toBe(getCurationRank('none'));
    expect(getCurationRank(null)).toBe(getCurationRank('none'));
    expect(getCurationRank('retired' as RepoCurationState)).toBe(getCurationRank('none'));
  });
});

describe('isInAutomationScope — mirrors the backend curated subset', () => {
  it('includes favorites and portfolio candidates', () => {
    expect(isInAutomationScope('favorite')).toBe(true);
    expect(isInAutomationScope('portfolio-candidate')).toBe(true);
  });

  it('EXCLUDES archived-ignore — the Release 2.7 never-touch guarantee', () => {
    expect(isInAutomationScope('archived-ignore')).toBe(false);
  });

  it('excludes uncurated repos, so automation never acts on the default portfolio', () => {
    expect(isInAutomationScope('none')).toBe(false);
    expect(isInAutomationScope(undefined)).toBe(false);
    expect(isInAutomationScope(null)).toBe(false);
  });

  it('excludes an unknown state — scope opts in, it does not opt out', () => {
    expect(isInAutomationScope('retired' as RepoCurationState)).toBe(false);
  });
});

describe('matchesCurationFilters', () => {
  it('matches every state when no curation filter is active', () => {
    for (const state of ALL_STATES) {
      expect(matchesCurationFilters(state, {}), `state '${state}' should pass an empty filter`).toBe(true);
    }
  });

  it('favoritesOnly keeps favorites and drops everything else', () => {
    expect(matchesCurationFilters('favorite', { favoritesOnly: true })).toBe(true);
    for (const state of ALL_STATES.filter((s) => s !== 'favorite')) {
      expect(matchesCurationFilters(state, { favoritesOnly: true })).toBe(false);
    }
  });

  it('candidatesOnly keeps candidates and drops everything else', () => {
    expect(matchesCurationFilters('portfolio-candidate', { candidatesOnly: true })).toBe(true);
    for (const state of ALL_STATES.filter((s) => s !== 'portfolio-candidate')) {
      expect(matchesCurationFilters(state, { candidatesOnly: true })).toBe(false);
    }
  });

  it('hideIgnored drops only archived repos', () => {
    expect(matchesCurationFilters('archived-ignore', { hideIgnored: true })).toBe(false);
    for (const state of ALL_STATES.filter((s) => s !== 'archived-ignore')) {
      expect(matchesCurationFilters(state, { hideIgnored: true })).toBe(true);
    }
  });

  it('hideIgnored keeps uncurated repos — it hides archived, not unlabelled', () => {
    expect(matchesCurationFilters(undefined, { hideIgnored: true })).toBe(true);
    expect(matchesCurationFilters(null, { hideIgnored: true })).toBe(true);
  });

  it('ANDs filters: favoritesOnly + candidatesOnly is an empty intersection', () => {
    for (const state of ALL_STATES) {
      expect(matchesCurationFilters(state, { favoritesOnly: true, candidatesOnly: true })).toBe(false);
    }
  });

  it('favoritesOnly + hideIgnored still keeps favorites', () => {
    expect(matchesCurationFilters('favorite', { favoritesOnly: true, hideIgnored: true })).toBe(true);
  });

  it('treats an explicitly false filter as inactive', () => {
    expect(matchesCurationFilters('archived-ignore', { favoritesOnly: false, hideIgnored: false })).toBe(true);
  });
});
