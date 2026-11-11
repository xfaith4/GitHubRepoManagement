import type { RoadmapExcludedItem } from '../types';

/**
 * Lane 0.22 (loop step 1): the open roadmap lines that were kept out of ranking
 * and dispatch, each with the rule that excluded it. Collapsed by default so the
 * row still leads with the work that will run; nothing renders when no line was
 * excluded.
 */
const CLASS_LABEL: Record<string, string> = {
  'done-statement': 'Already done',
  deferred: 'Deferred',
  guidance: 'Guidance',
  fragment: 'Fragment',
};

interface ExcludedItemsDisclosureProps {
  items?: RoadmapExcludedItem[] | null;
  count?: number | null;
  modelVersion?: string | null;
}

export function ExcludedItemsDisclosure({ items, count, modelVersion }: ExcludedItemsDisclosureProps) {
  const list = Array.isArray(items) ? items : [];
  const total = Math.max(Number(count ?? 0), list.length);
  if (total === 0) return null;

  return (
    <details
      data-testid="excluded-items"
      className="mt-1 text-xs text-gray-400"
      onClick={event => event.stopPropagation()}
    >
      <summary className="cursor-pointer select-none text-gray-400 hover:text-gray-200">
        Excluded ({total})
      </summary>
      <ul className="mt-1 space-y-1 rounded border border-gray-700 bg-gray-900/70 px-2 py-1.5">
        {list.map((item, index) => (
          <li key={item.itemHash || `${index}-${item.text}`} data-testid="excluded-item">
            <span className="text-gray-200">{item.text || '(empty line)'}</span>
            <span className="text-gray-500"> - {CLASS_LABEL[item.itemClass] ?? item.itemClass}: {item.reason}</span>
          </li>
        ))}
        {list.length < total && (
          <li className="text-gray-500">{total - list.length} more not listed in this response.</li>
        )}
      </ul>
      {modelVersion && (
        <div className="mt-1 text-gray-500">Judged by item-quality model {modelVersion} (backend/config/roadmap-item-rules.json).</div>
      )}
    </details>
  );
}

export default ExcludedItemsDisclosure;
