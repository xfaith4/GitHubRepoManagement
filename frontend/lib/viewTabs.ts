// Desktop view-tab presentation (Release 2.7 Phase D — Dashboard decomposition).
//
// The tab strip previously inlined six near-identical buttons in Dashboard.tsx,
// four of which hardcoded their label while two read `VIEW_META`. That is the
// drift `viewMeta.ts` exists to prevent, so the extracted strip drives every tab
// from VIEW_META and keeps only the per-view accent here — presentation, not
// meaning.
//
// The badge rule was also stated three different ways inline (a truthiness
// check, `> 0`, and `> 0` again). It is one rule, so it lives in one function.

import { type ViewKey } from '../viewMeta';

export interface ViewTabAccent {
  /** Border + text + background classes for the active tab. */
  active: string;
  /** Badge pill classes when the count is live. */
  badge: string;
}

const INACTIVE_TAB_CLASS = 'border-transparent text-gray-400 hover:text-gray-200 hover:bg-gray-700/20';

export const VIEW_TAB_ACCENTS: Record<ViewKey, ViewTabAccent> = {
  'repos': {
    active: 'border-indigo-500 text-indigo-300 bg-gray-700/40',
    badge: 'bg-indigo-700 text-indigo-100',
  },
  'insights': {
    active: 'border-sky-500 text-sky-300 bg-gray-700/40',
    badge: 'bg-sky-700 text-sky-100',
  },
  'operations': {
    active: 'border-sky-500 text-sky-300 bg-gray-700/40',
    badge: 'bg-sky-700 text-sky-100',
  },
  'work-queue': {
    active: 'border-indigo-500 text-indigo-300 bg-gray-700/40',
    badge: 'bg-green-700 text-green-100',
  },
  'execution-queue': {
    active: 'border-blue-500 text-blue-300 bg-gray-700/40',
    badge: 'bg-blue-700 text-blue-100',
  },
  'dependencies': {
    active: 'border-teal-500 text-teal-300 bg-gray-700/40',
    badge: 'bg-teal-700 text-teal-100',
  },
};

/** Carried-over badges are amber-ringed regardless of the view's own accent. */
export const CARRIED_OVER_BADGE_CLASS = 'bg-amber-800 text-amber-100 ring-1 ring-amber-500/60';

export function getViewTabClass(key: ViewKey, activeView: ViewKey): string {
  return key === activeView ? VIEW_TAB_ACCENTS[key].active : INACTIVE_TAB_CLASS;
}

export interface ViewTabBadge {
  count: number;
  /**
   * True when the count comes from persisted data that the live scope no longer
   * backs — a stale number the operator would otherwise read as current.
   */
  carriedOver?: boolean;
  /** Explanation shown on hover; only meaningful for a carried-over badge. */
  title?: string;
}

export type ViewTabBadges = Partial<Record<ViewKey, ViewTabBadge>>;

/**
 * A tab shows a badge only for a positive count. A zero count renders nothing
 * rather than a "0" pill — an empty queue is the resting state, and badging it
 * would put a permanent marker on most tabs.
 */
export function getVisibleTabBadge(badges: ViewTabBadges, key: ViewKey): ViewTabBadge | null {
  const badge = badges[key];
  if (!badge) return null;
  if (!Number.isFinite(badge.count) || badge.count <= 0) return null;
  return badge;
}

export function getTabBadgeClass(key: ViewKey, carriedOver?: boolean): string {
  return carriedOver ? CARRIED_OVER_BADGE_CLASS : VIEW_TAB_ACCENTS[key].badge;
}
