// @vitest-environment jsdom
//
// Lane 0.22 (loop step 1) - each repository shows "Excluded (n)" with the reason
// each open line was kept out of ranking and dispatch.
import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import ExcludedItemsDisclosure from './ExcludedItemsDisclosure';
import type { RoadmapExcludedItem } from '../types';

afterEach(() => cleanup());

const ITEMS: RoadmapExcludedItem[] = [
  { text: 'Done: the import route returns JSON', section: 'Next', tags: [], itemClass: 'done-statement', ruleId: 'done-prefix', reason: 'the line opens with Done:', itemHash: 'aa11' },
  { text: 'Cache the parsed config [non-blocker]', section: 'Next', tags: ['non-blocker'], itemClass: 'deferred', ruleId: 'deferred-tag', reason: 'tagged non-blocker', itemHash: 'bb22' },
];

describe('ExcludedItemsDisclosure', () => {
  it('shows the count and every excluded line with its reason', () => {
    render(<ExcludedItemsDisclosure items={ITEMS} count={2} modelVersion="1.0" />);
    expect(screen.getByText('Excluded (2)')).toBeInTheDocument();
    const rows = screen.getAllByTestId('excluded-item');
    expect(rows).toHaveLength(2);
    expect(rows[0]).toHaveTextContent('Done: the import route returns JSON');
    expect(rows[0]).toHaveTextContent('Already done: the line opens with Done:');
    expect(rows[1]).toHaveTextContent('Deferred: tagged non-blocker');
    expect(screen.getByText(/item-quality model 1\.0/)).toBeInTheDocument();
  });

  it('renders nothing when no line was excluded', () => {
    const { container } = render(<ExcludedItemsDisclosure items={[]} count={0} />);
    expect(container).toBeEmptyDOMElement();
  });

  it('says how many lines the response did not list', () => {
    render(<ExcludedItemsDisclosure items={ITEMS.slice(0, 1)} count={3} />);
    expect(screen.getByText('Excluded (3)')).toBeInTheDocument();
    expect(screen.getByText('2 more not listed in this response.')).toBeInTheDocument();
  });
});
