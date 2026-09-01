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

// Nocturne (MIGRATION.md §2): ONE accent, used as line and text, never as a
// fill. The seven per-view hues that used to live here -- emerald, indigo,
// sky, sky, indigo, blue, teal -- were decoration, not meaning: a tab is
// already identified by its label and its position, so a colour per tab told
// the operator nothing a second glance did not, while spending six of the
// palette's hues on it. Status colour has to stay legible against the
// chrome, and it cannot if the chrome is also coloured.
//
// The active tab is the accent plus a 2px accent rail drawn as an inset
// shadow, which is §4's rule -- the rail sits outside the box model, so
// switching tabs never shifts the strip by a pixel.
const INACTIVE_TAB_CLASS = 'text-text/62 hover:text-text hover:bg-text/6';
const ACTIVE_TAB_CLASS = 'text-accent shadow-[inset_0_-2px_0_0_var(--color-accent)]';

/** Every view now shares the accent; the record keeps the per-view shape so a
 *  future view cannot forget to declare itself. */
export const VIEW_TAB_ACCENTS: Record<ViewKey, ViewTabAccent> = {
  'today': { active: ACTIVE_TAB_CLASS, badge: 'bg-accent-800 text-accent-100' },
  'repos': { active: ACTIVE_TAB_CLASS, badge: 'bg-accent-800 text-accent-100' },
  'insights': { active: ACTIVE_TAB_CLASS, badge: 'bg-accent-800 text-accent-100' },
  'operations': { active: ACTIVE_TAB_CLASS, badge: 'bg-accent-800 text-accent-100' },
  'work-queue': { active: ACTIVE_TAB_CLASS, badge: 'bg-accent-800 text-accent-100' },
  'execution-queue': { active: ACTIVE_TAB_CLASS, badge: 'bg-accent-800 text-accent-100' },
  'dependencies': { active: ACTIVE_TAB_CLASS, badge: 'bg-accent-800 text-accent-100' },
};

/** Carried-over badges stay warn-coloured — a stale count is an operational
 *  state, and §3's warn hue is what states it everywhere else. */
export const CARRIED_OVER_BADGE_CLASS = 'bg-status-warn/25 text-status-warn-text ring-1 ring-status-warn/50';

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
