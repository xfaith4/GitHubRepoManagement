import React from 'react';
import { VIEW_META, VIEW_META_BY_KEY, type ViewKey } from '../viewMeta';
import {
  getTabBadgeClass,
  getViewTabClass,
  getVisibleTabBadge,
  type ViewTabBadges,
} from '../lib/viewTabs';

interface DashboardViewTabsProps {
  activeView: ViewKey;
  onSelectView: (view: ViewKey) => void;
  badges?: ViewTabBadges;
}

/**
 * The desktop view-tab strip and the per-view purpose subtitle (Release 2.6
 * Phase 2), extracted from Dashboard.tsx in Release 2.7 Phase D. The mobile
 * bottom nav mirrors these from the same `VIEW_META`.
 *
 * Every tab is rendered from VIEW_META rather than hardcoded, so a label
 * change lands on the desktop tab, the mobile nav, and the orientation overlay
 * at once.
 */
const DashboardViewTabs: React.FC<DashboardViewTabsProps> = ({ activeView, onSelectView, badges = {} }) => (
  <>
    {/* View tabs — desktop only; the mobile bottom nav mirrors these */}
    <div className="hidden md:flex border-b border-gray-700 px-4 pt-3 gap-1">
      {VIEW_META.map(({ key, label }) => {
        const badge = getVisibleTabBadge(badges, key);
        return (
          <button
            key={key}
            onClick={() => onSelectView(key)}
            className={`px-4 py-2 text-sm font-medium rounded-t border-b-2 transition-colors flex items-center gap-1.5 ${getViewTabClass(key, activeView)}`}
          >
            {label}
            {badge && (
              <span
                data-testid={`${key}-tab-badge`}
                data-carried-over={badge.carriedOver || undefined}
                title={badge.carriedOver ? badge.title : undefined}
                className={`inline-flex items-center justify-center w-5 h-5 text-xs rounded-full font-semibold ${getTabBadgeClass(key, badge.carriedOver)}`}
              >
                {badge.count}
              </span>
            )}
          </button>
        );
      })}
    </div>

    {/* The question this view answers (Release 3.6 M3), then the Release 2.6
        purpose subtitle. A label names a place; the question names the reason
        to be there, which is what an operator is actually choosing between. */}
    <div className="px-4 py-2 border-b border-gray-700/60">
      <p data-testid="view-question" className="text-xs text-gray-200 font-medium">
        {VIEW_META_BY_KEY[activeView].question}
      </p>
      <p data-testid="view-subtitle" className="text-xs text-gray-400 mt-0.5">
        {VIEW_META_BY_KEY[activeView].subtitle}
      </p>
    </div>
  </>
);

export default DashboardViewTabs;
