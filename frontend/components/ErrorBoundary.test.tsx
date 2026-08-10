// @vitest-environment jsdom
//
// DOM tests for the error boundary (frontend hardening, 2026-08-10). The
// contract: a render-time throw becomes a named, recoverable card — never a
// white screen — and "Try again" genuinely re-renders the children.
import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import ErrorBoundary from './ErrorBoundary';

// React logs caught boundary errors via console.error; keep test output clean
// without hiding anything else.
beforeEach(() => vi.spyOn(console, 'error').mockImplementation(() => {}));
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

/** Throws on the first render, renders happily after `healed` flips. */
function makeThrowOnce() {
  const state = { healed: false };
  const ThrowOnce: React.FC = () => {
    if (!state.healed) {
      throw new Error('widget exploded during render');
    }
    return <div data-testid="healed-child">recovered content</div>;
  };
  return { state, ThrowOnce };
}

describe('ErrorBoundary', () => {
  it('renders children untouched when nothing throws', () => {
    render(
      <ErrorBoundary label="The Insights view">
        <div data-testid="happy-child">fine</div>
      </ErrorBoundary>
    );
    expect(screen.getByTestId('happy-child')).toBeInTheDocument();
    expect(screen.queryByTestId('error-boundary-card')).not.toBeInTheDocument();
  });

  it('replaces a throwing child with a named error card, not a white screen', () => {
    const { ThrowOnce } = makeThrowOnce();
    render(
      <ErrorBoundary label="The Insights view">
        <ThrowOnce />
      </ErrorBoundary>
    );
    const card = screen.getByTestId('error-boundary-card');
    expect(card).toHaveTextContent('The Insights view hit an error');
    expect(card).toHaveTextContent('widget exploded during render');
    expect(screen.getByRole('alert')).toBe(card);
  });

  it('recovers real content when Try again is clicked after the cause is gone', () => {
    const { state, ThrowOnce } = makeThrowOnce();
    render(
      <ErrorBoundary label="The Insights view">
        <ThrowOnce />
      </ErrorBoundary>
    );
    expect(screen.getByTestId('error-boundary-card')).toBeInTheDocument();
    state.healed = true;
    fireEvent.click(screen.getByRole('button', { name: 'Try again' }));
    expect(screen.getByTestId('healed-child')).toBeInTheDocument();
    expect(screen.queryByTestId('error-boundary-card')).not.toBeInTheDocument();
  });

  it('shows the card again if the child still throws after reset', () => {
    const { ThrowOnce } = makeThrowOnce();
    render(
      <ErrorBoundary label="The Insights view">
        <ThrowOnce />
      </ErrorBoundary>
    );
    fireEvent.click(screen.getByRole('button', { name: 'Try again' }));
    expect(screen.getByTestId('error-boundary-card')).toBeInTheDocument();
  });
});
