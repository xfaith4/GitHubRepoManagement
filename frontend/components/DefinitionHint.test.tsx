// @vitest-environment jsdom
//
// Release 2.9 — a tap equivalent for a hover-only definition.
//
// The failure this prevents is invisible on a desktop and total on a phone:
// a definition that exists only in a `title` attribute is unreachable without
// a mouse. These assert that the definition is reachable BY ACTIVATION — the
// thing a finger can do — and that the desktop hover path was added to, not
// replaced.
import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import DefinitionHint from './DefinitionHint';

const DEFINITION = 'Change-aware indexing: unchanged repositories are reused.';

afterEach(() => cleanup());

describe('DefinitionHint', () => {
  it('hides the definition until it is asked for', () => {
    render(<DefinitionHint definition={DEFINITION} data-testid="hint">Last scan:</DefinitionHint>);
    expect(screen.getByText('Last scan:')).toBeInTheDocument();
    expect(screen.queryByTestId('hint-detail')).not.toBeInTheDocument();
    expect(screen.getByTestId('hint')).toHaveAttribute('aria-expanded', 'false');
  });

  it('discloses the definition on activation — the path a finger has', () => {
    render(<DefinitionHint definition={DEFINITION} data-testid="hint">Last scan:</DefinitionHint>);
    fireEvent.click(screen.getByTestId('hint'));
    expect(screen.getByTestId('hint-detail')).toHaveTextContent(DEFINITION);
    expect(screen.getByTestId('hint')).toHaveAttribute('aria-expanded', 'true');
  });

  it('toggles closed again', () => {
    render(<DefinitionHint definition={DEFINITION} data-testid="hint">Last scan:</DefinitionHint>);
    fireEvent.click(screen.getByTestId('hint'));
    fireEvent.click(screen.getByTestId('hint'));
    expect(screen.queryByTestId('hint-detail')).not.toBeInTheDocument();
  });

  it('keeps the desktop hover path: the title still carries the definition', () => {
    render(<DefinitionHint definition={DEFINITION} data-testid="hint">Last scan:</DefinitionHint>);
    // This adds a path for touch; it must not remove the one mouse users have.
    expect(screen.getByTestId('hint')).toHaveAttribute('title', DEFINITION);
  });

  it('names itself for a screen reader and points at what it controls', () => {
    render(<DefinitionHint definition={DEFINITION} data-testid="hint">Last scan:</DefinitionHint>);
    const button = screen.getByRole('button', { name: 'Show definition' });
    const controls = button.getAttribute('aria-controls');
    expect(controls).toBeTruthy();
    fireEvent.click(button);
    expect(screen.getByRole('button', { name: 'Hide definition' })).toBeInTheDocument();
    expect(document.getElementById(controls as string)).toHaveTextContent(DEFINITION);
  });
});
