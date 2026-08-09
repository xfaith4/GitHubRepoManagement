import { describe, it, expect } from 'vitest';
import {
  CARRIED_OVER_BADGE_CLASS,
  VIEW_TAB_ACCENTS,
  getTabBadgeClass,
  getViewTabClass,
  getVisibleTabBadge,
  type ViewTabBadges,
} from './viewTabs';
import { VIEW_META, type ViewKey } from '../viewMeta';

describe('VIEW_TAB_ACCENTS — every view is renderable', () => {
  it('has an accent for every view VIEW_META declares', () => {
    for (const { key } of VIEW_META) {
      expect(VIEW_TAB_ACCENTS[key], `missing accent for view '${key}'`).toBeDefined();
      expect(VIEW_TAB_ACCENTS[key].active.length).toBeGreaterThan(0);
      expect(VIEW_TAB_ACCENTS[key].badge.length).toBeGreaterThan(0);
    }
  });

  it('declares no accent for a view VIEW_META does not have', () => {
    const metaKeys = VIEW_META.map((meta) => meta.key).sort();
    expect(Object.keys(VIEW_TAB_ACCENTS).sort()).toEqual(metaKeys);
  });
});

describe('getViewTabClass', () => {
  it('gives the active tab its own accent', () => {
    expect(getViewTabClass('operations', 'operations')).toBe(VIEW_TAB_ACCENTS.operations.active);
  });

  it('gives every inactive tab the same muted class', () => {
    const inactive = VIEW_META.filter((meta) => meta.key !== 'repos').map((meta) =>
      getViewTabClass(meta.key, 'repos'),
    );
    expect(new Set(inactive).size).toBe(1);
    expect(inactive[0]).not.toBe(VIEW_TAB_ACCENTS.repos.active);
  });

  it('marks exactly one tab active for any given view', () => {
    for (const { key: activeView } of VIEW_META) {
      const activeCount = VIEW_META.filter(
        (meta) => getViewTabClass(meta.key, activeView) === VIEW_TAB_ACCENTS[meta.key].active,
      ).length;
      expect(activeCount, `view '${activeView}' should light exactly one tab`).toBe(1);
    }
  });
});

describe('getVisibleTabBadge — positive counts only', () => {
  const badges: ViewTabBadges = {
    'operations': { count: 4, carriedOver: false },
    'work-queue': { count: 0 },
    'dependencies': { count: 12 },
  };

  it('shows a badge for a positive count', () => {
    expect(getVisibleTabBadge(badges, 'operations')?.count).toBe(4);
    expect(getVisibleTabBadge(badges, 'dependencies')?.count).toBe(12);
  });

  it('hides a zero count rather than rendering a "0" pill', () => {
    expect(getVisibleTabBadge(badges, 'work-queue')).toBeNull();
  });

  it('hides a tab with no badge descriptor at all', () => {
    expect(getVisibleTabBadge(badges, 'repos')).toBeNull();
    expect(getVisibleTabBadge({}, 'operations')).toBeNull();
  });

  it('hides a negative or non-finite count instead of rendering it', () => {
    expect(getVisibleTabBadge({ repos: { count: -1 } }, 'repos')).toBeNull();
    expect(getVisibleTabBadge({ repos: { count: Number.NaN } }, 'repos')).toBeNull();
  });

  it('preserves the carried-over flag and its explanation', () => {
    const carried: ViewTabBadges = {
      operations: { count: 9, carriedOver: true, title: 'Carried over from the last completed scan' },
    };
    const badge = getVisibleTabBadge(carried, 'operations');
    expect(badge?.carriedOver).toBe(true);
    expect(badge?.title).toContain('Carried over');
  });
});

describe('getTabBadgeClass', () => {
  it('uses the view accent for a live count', () => {
    for (const { key } of VIEW_META) {
      expect(getTabBadgeClass(key, false)).toBe(VIEW_TAB_ACCENTS[key].badge);
      expect(getTabBadgeClass(key, undefined)).toBe(VIEW_TAB_ACCENTS[key].badge);
    }
  });

  it('overrides every view accent with the amber carried-over style', () => {
    // A stale count must look the same wherever it appears — the operator reads
    // amber as "this number does not describe the current scan".
    for (const { key } of VIEW_META) {
      expect(getTabBadgeClass(key, true)).toBe(CARRIED_OVER_BADGE_CLASS);
    }
  });
});
