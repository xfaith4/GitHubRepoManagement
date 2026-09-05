// @vitest-environment jsdom
//
// The version chip the operator asked for: after a change lands, confirm the
// portal in the browser is the updated one.
//
// The logic matrix lives in lib/buildStamp.test.ts. What only a DOM test can
// prove is that the chip actually renders both stamps when they disagree —
// a chip that silently shows the UI's own commit would look correct in every
// screenshot while hiding the exact condition it exists to surface.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, cleanup, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import BuildStampIndicator from './BuildStampIndicator';
import * as apiClient from '../services/apiClient';

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe('BuildStampIndicator', () => {
  it('shows one version when the host runs the same commit as the bundle', async () => {
    // vitest.config.ts defines __BUILD_COMMIT__ as 'testsha'.
    vi.spyOn(apiClient, 'getPortalVersion').mockResolvedValue({
      commit: 'testsha',
      branch: 'main',
      startedAtUtc: '2026-09-05T12:00:00.000Z',
    });

    render(<BuildStampIndicator />);

    await waitFor(() => {
      expect(screen.getByTestId('build-stamp')).toHaveAttribute('data-state', 'matched');
    });
    expect(screen.getByTestId('build-stamp')).toHaveTextContent('testsha');
  });

  it('names both commits when the host is running different code', async () => {
    vi.spyOn(apiClient, 'getPortalVersion').mockResolvedValue({
      commit: 'othersh',
      branch: 'main',
      startedAtUtc: '2026-09-05T12:00:00.000Z',
    });

    render(<BuildStampIndicator />);

    await waitFor(() => {
      expect(screen.getByTestId('build-stamp')).toHaveAttribute('data-state', 'mismatched');
    });
    const chip = screen.getByTestId('build-stamp');
    expect(chip).toHaveTextContent('testsha');
    expect(chip).toHaveTextContent('othersh');
    // The remedy is named where the operator is looking, not in a log.
    expect(chip.getAttribute('title')).toContain('restarted');
  });

  it('does not claim a match when the host does not answer', async () => {
    vi.spyOn(apiClient, 'getPortalVersion').mockResolvedValue(null);

    render(<BuildStampIndicator />);

    await waitFor(() => {
      expect(screen.getByTestId('build-stamp')).toHaveAttribute('data-state', 'api-unknown');
    });
  });

  it('renders without throwing before the host has answered', () => {
    vi.spyOn(apiClient, 'getPortalVersion').mockReturnValue(new Promise(() => {}));
    render(<BuildStampIndicator />);
    expect(screen.getByTestId('build-stamp')).toBeInTheDocument();
  });
});
