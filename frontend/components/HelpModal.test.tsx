// @vitest-environment jsdom
//
// The Help dialog is now the console's single reference surface: the guide, the
// status-word definitions, and the backend API reference, opened from the page
// header instead of from one tab's action bar.
//
// These tests are about the COMBINATION holding. `lib/glossary.test.ts` proves
// the definitions agree with `docs/reference/status-vocabulary.md`; nothing
// there notices if the dialog stops rendering them. So the assertions below are
// deliberately about what an operator can actually reach: both tabs exist, the
// definitions are on screen with their basis, the search narrows them, and the
// dialog can be left without the mouse.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup, within } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import HelpModal from './HelpModal';
import { allGlossaryTerms } from '../lib/glossary';

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

function open(overrides: Partial<React.ComponentProps<typeof HelpModal>> = {}) {
  const onClose = vi.fn();
  render(<HelpModal isOpen onClose={onClose} {...overrides} />);
  return { onClose };
}

describe('HelpModal is one dialog for two former buttons', () => {
  it('offers both Definitions and API Reference from the same dialog', () => {
    open();
    expect(screen.getByTestId('help-tab-definitions')).toBeInTheDocument();
    expect(screen.getByTestId('help-tab-api')).toBeInTheDocument();
  });

  it('renders the API reference in place, not as a nested dialog', () => {
    open();
    fireEvent.click(screen.getByTestId('help-tab-api'));
    expect(screen.getByTestId('api-reference')).toBeInTheDocument();
    // One dialog, not two: a nested role="dialog" would mean the reference
    // kept its own chrome and the "combined" claim is cosmetic.
    expect(screen.getAllByRole('dialog')).toHaveLength(1);
  });

  it('lands on the tab it was asked for', () => {
    open({ initialTab: 'definitions' });
    expect(screen.getByTestId('help-tab-definitions')).toHaveAttribute('aria-current', 'page');
    expect(screen.getByTestId('glossary-filter')).toBeInTheDocument();
  });
});

describe('the definitions tab', () => {
  it('shows every glossary term with its computed-from basis', () => {
    open({ initialTab: 'definitions' });
    // Not a spot check: the operator asked for definitions of Dirty, Stale,
    // PRs and L1/L2/L3, and a partial render would still satisfy any single
    // getByText. Every documented term must be on screen.
    for (const term of allGlossaryTerms()) {
      expect(screen.getAllByText(term.term).length).toBeGreaterThan(0);
    }
    expect(screen.getAllByText(/Computed from:/).length).toBe(allGlossaryTerms().length);
  });

  it('defines the terms the operator actually asked about', () => {
    open({ initialTab: 'definitions' });
    expect(screen.getByText('Dirty')).toBeInTheDocument();
    expect(screen.getByText('Stale / Behind')).toBeInTheDocument();
    expect(screen.getByText('PRs')).toBeInTheDocument();
    expect(screen.getByText('L1 — Informal')).toBeInTheDocument();
    expect(screen.getByText('L2 — Structured')).toBeInTheDocument();
    expect(screen.getByText('L3 — Contract-Ready')).toBeInTheDocument();
  });

  it('separates the two Blocked meanings instead of showing one', () => {
    // The audit's central complaint. If these ever collapse back into a single
    // "Blocked" entry, the glossary is asserting the contradiction rather than
    // explaining it.
    open({ initialTab: 'definitions' });
    expect(screen.getByText('Blocked (dispatch)')).toBeInTheDocument();
    expect(screen.getByText('Blocked (execution lane)')).toBeInTheDocument();
  });

  it('narrows to matching terms as you search, and says so when nothing matches', () => {
    open({ initialTab: 'definitions' });
    const filter = screen.getByTestId('glossary-filter');

    fireEvent.change(filter, { target: { value: 'pushed_at' } });
    const drift = screen.getByTestId('glossary-group-remote-drift');
    expect(within(drift).getByText('Stale / Behind')).toBeInTheDocument();
    expect(screen.queryByTestId('glossary-group-roadmap-maturity')).not.toBeInTheDocument();

    fireEvent.change(filter, { target: { value: 'zzz-not-a-term' } });
    expect(screen.getByTestId('glossary-no-match')).toBeInTheDocument();
  });
});

describe('the dialog can be left without a mouse', () => {
  it('closes on Escape', () => {
    const { onClose } = open();
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(onClose).toHaveBeenCalled();
  });

  it('names itself for assistive technology', () => {
    open();
    const dialog = screen.getByRole('dialog');
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(dialog).toHaveAccessibleName('GitHub Repo Manager Guide');
  });
});
