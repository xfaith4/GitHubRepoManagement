import React, { useEffect, useRef, useState } from 'react';
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

/** Stable id for a tab button, so its panel can point back at it. */
export const viewTabId = (key: ViewKey) => `view-tab-${key}`;
/** Stable id for the panel a tab controls. Rendered by Dashboard. */
export const viewPanelId = (key: ViewKey) => `view-panel-${key}`;

/**
 * The desktop view-tab strip and the per-view purpose subtitle (Release 2.6
 * Phase 2), extracted from Dashboard.tsx in Release 2.7 Phase D. The mobile
 * bottom nav mirrors these from the same `VIEW_META`.
 *
 * Every tab is rendered from VIEW_META rather than hardcoded, so a label
 * change lands on the desktop tab, the mobile nav, and the orientation overlay
 * at once.
 *
 * Keyboard model (audit follow-up): this is a real ARIA tablist, so the seven
 * views are one stop in the Tab order rather than seven, and arrows move
 * between them. Activation is MANUAL -- an arrow moves focus, Enter or Space
 * switches the view -- because switching a view here starts work (the
 * dependency graph fetches on activation), and automatic activation would fire
 * one fetch per tab arrowed past.
 */
const DashboardViewTabs: React.FC<DashboardViewTabsProps> = ({ activeView, onSelectView, badges = {} }) => {
  // Roving tabindex: which tab the arrows have landed on, which is not
  // necessarily the view being shown while the operator is still choosing.
  // Held as an override rather than a mirror of `activeView`, so there is no
  // effect syncing one piece of state to another — the arrows set it, and a
  // view change clears it.
  const [focusOverride, setFocusOverride] = useState<ViewKey | null>(null);
  const [previousActive, setPreviousActive] = useState<ViewKey>(activeView);
  const tabRefs = useRef(new Map<ViewKey, HTMLButtonElement | null>());
  // Only steal focus when the operator is actually arrowing, never on the
  // initial render or on a view change driven from elsewhere in the app.
  const shouldFocus = useRef(false);

  // Adjusting state during render when a prop changes — React's documented
  // alternative to a syncing effect, and it avoids the extra render pass an
  // effect would cost on every tab switch.
  if (previousActive !== activeView) {
    setPreviousActive(activeView);
    setFocusOverride(null);
  }

  const focusedView = focusOverride ?? activeView;

  useEffect(() => {
    if (!shouldFocus.current) return;
    shouldFocus.current = false;
    tabRefs.current.get(focusedView)?.focus();
  }, [focusedView]);

  const moveFocus = (to: ViewKey) => {
    shouldFocus.current = true;
    setFocusOverride(to);
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    const index = VIEW_META.findIndex(meta => meta.key === focusedView);
    if (index < 0) return;
    const last = VIEW_META.length - 1;

    switch (event.key) {
      case 'ArrowRight':
        event.preventDefault();
        moveFocus(VIEW_META[index === last ? 0 : index + 1].key);
        break;
      case 'ArrowLeft':
        event.preventDefault();
        moveFocus(VIEW_META[index === 0 ? last : index - 1].key);
        break;
      case 'Home':
        event.preventDefault();
        moveFocus(VIEW_META[0].key);
        break;
      case 'End':
        event.preventDefault();
        moveFocus(VIEW_META[last].key);
        break;
      case 'Enter':
      case ' ':
        event.preventDefault();
        onSelectView(focusedView);
        break;
      default:
        break;
    }
  };

  return (
    <>
      {/* View tabs — desktop only; the mobile bottom nav mirrors these */}
      <div
        role="tablist"
        aria-label="Views"
        aria-orientation="horizontal"
        onKeyDown={onKeyDown}
        className="hidden md:flex border-b border-gray-700 px-4 pt-3 gap-1"
      >
        {VIEW_META.map(({ key, label }) => {
          const badge = getVisibleTabBadge(badges, key);
          const isActive = key === activeView;
          return (
            <button
              key={key}
              ref={node => { tabRefs.current.set(key, node); }}
              role="tab"
              id={viewTabId(key)}
              aria-selected={isActive}
              aria-controls={viewPanelId(key)}
              tabIndex={key === focusedView ? 0 : -1}
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
};

export default DashboardViewTabs;
