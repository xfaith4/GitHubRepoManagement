// Operator curation = the automation scope selector (Release 2.7 Phase D).
//
// Curation is not cosmetic. Release 2.7's contract is that scheduled automation
// acts on the curated subset — favorites and portfolio candidates — and that
// `archived-ignore` repos are NEVER touched. The backend enforces that scope;
// these helpers are the frontend half, deciding what the operator is shown as
// in scope. The two must agree, because a grid that still lists an ignored repo
// under an automation-scoped filter tells the operator that automation will act
// on something it will silently skip.
//
// Extracted from RepoGrid so the predicates and the ordering are unit-testable
// without mounting the grid.

import { type RepoCurationState } from '../types';

export interface CurationBadgePresentation {
  className: string;
  label: string;
  title: string;
}

/**
 * `none` deliberately has no badge — an uncurated repo is the baseline, and
 * badging it would put a chip on most of the portfolio.
 */
export function getCurationBadgeConfig(state?: RepoCurationState | null): CurationBadgePresentation | null {
  switch (state) {
    case 'favorite':
      return {
        className: 'bg-yellow-900/40 text-yellow-200 border-yellow-600/50',
        label: '★ Favorite',
        title: 'Operator curation: Favorite — always surfaced first in priority order',
      };
    case 'portfolio-candidate':
      return {
        className: 'bg-sky-900/40 text-sky-300 border-sky-700/50',
        label: '◆ Candidate',
        title: 'Operator curation: Portfolio Candidate — being evaluated for active work',
      };
    case 'archived-ignore':
      return {
        className: 'bg-gray-800/70 text-gray-400 border-gray-600/50',
        label: '⊘ Ignored',
        title: 'Operator curation: Archived / Ignore — suppressed by the "Hide ignored" filter',
      };
    default:
      return null;
  }
}

/**
 * Priority sort rank: favorites, then candidates, then the uncurated tail, then
 * archived last. Uncurated (rank 2) sits AHEAD of archived (rank 3) on purpose —
 * a repo the operator has parked should never outrank one they have not yet
 * triaged.
 */
export function getCurationRank(state?: RepoCurationState | null): number {
  switch (state) {
    case 'favorite':
      return 0;
    case 'portfolio-candidate':
      return 1;
    case 'archived-ignore':
      return 3;
    default:
      return 2;
  }
}

/**
 * True when automation's curated subset includes this repo: favorites and
 * portfolio candidates only. Mirrors the backend's automation scope, which
 * excludes uncurated and archived repos alike.
 */
export function isInAutomationScope(state?: RepoCurationState | null): boolean {
  return state === 'favorite' || state === 'portfolio-candidate';
}

export interface CurationQuickFilters {
  favoritesOnly?: boolean;
  candidatesOnly?: boolean;
  hideIgnored?: boolean;
}

/**
 * The curation half of the grid's quick-filter predicate. Each filter is
 * independently ANDed, and an unset filter matches everything — so
 * `favoritesOnly` + `candidatesOnly` together match nothing, since no repo
 * holds two curation states at once. That is the honest result: the operator
 * asked for an empty intersection.
 */
export function matchesCurationFilters(
  state: RepoCurationState | null | undefined,
  filters: CurationQuickFilters,
): boolean {
  const matchesFavorites = !filters.favoritesOnly || state === 'favorite';
  const matchesCandidates = !filters.candidatesOnly || state === 'portfolio-candidate';
  const matchesHideIgnored = !filters.hideIgnored || state !== 'archived-ignore';
  return matchesFavorites && matchesCandidates && matchesHideIgnored;
}
