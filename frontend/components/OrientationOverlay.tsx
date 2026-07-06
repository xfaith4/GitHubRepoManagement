import React from 'react';
import { VIEW_META } from '../viewMeta';

// First-visit orientation overlay (Release 2.6 Phase 2). A single dismissible
// modal that names each of the six tabs and its one-line purpose so a new
// operator can self-orient without trial and error. Dismissal is persisted to
// localStorage so it never reappears once acknowledged.

const STORAGE_KEY = 'ghrm.orientationDismissed.v1';

export function hasSeenOrientation(): boolean {
  try {
    return typeof localStorage !== 'undefined' && localStorage.getItem(STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

interface OrientationOverlayProps {
  onDismiss: () => void;
}

const OrientationOverlay: React.FC<OrientationOverlayProps> = ({ onDismiss }) => {
  const dismiss = () => {
    try {
      localStorage.setItem(STORAGE_KEY, '1');
    } catch {
      /* localStorage unavailable — dismiss for this session only */
    }
    onDismiss();
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="App orientation"
      data-testid="orientation-overlay"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4"
    >
      <div className="w-full max-w-lg rounded-xl border border-gray-700 bg-gray-900 shadow-2xl max-h-[90vh] overflow-y-auto">
        <div className="px-5 py-4 border-b border-gray-700">
          <h2 className="text-lg font-bold text-gray-100">Welcome — here's the map</h2>
          <p className="text-sm text-gray-400 mt-1">
            Six tabs, each with one job. Repository Grid is your main workspace; Insights is
            read-only analytics; Operations and the two queues handle dispatch.
          </p>
        </div>
        <ul className="px-5 py-2 divide-y divide-gray-800">
          {VIEW_META.map(v => (
            <li key={v.key} className="py-2.5">
              <div className="text-sm font-semibold text-gray-100">{v.label}</div>
              <div className="text-xs text-gray-400 mt-0.5">{v.subtitle}</div>
            </li>
          ))}
        </ul>
        <div className="px-5 py-4 border-t border-gray-700 flex justify-end">
          <button
            type="button"
            onClick={dismiss}
            data-testid="orientation-dismiss"
            className="px-4 py-2 rounded-md bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium transition-colors"
          >
            Got it
          </button>
        </div>
      </div>
    </div>
  );
};

export default OrientationOverlay;
