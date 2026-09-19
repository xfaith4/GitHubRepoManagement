// @vitest-environment jsdom
//
// H38-19b — Settings names each provider and what to do about it.
//
// Ben asked for this surface directly: whether an account exists for any of the
// three providers has to be visible without reading a log. The failures these
// prevent: a green tick claiming a provider works when nobody has tested the
// account (A21 — availability answers *installed and switched on*, never
// authenticated); an offer to disable something that is not installed; and an
// opt-out that flips the row optimistically and lies when the write fails.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import SettingsModal from './SettingsModal';
import * as apiClient from '../services/apiClient';
import type { AppSettings, ProviderAvailability } from '../types';

vi.mock('../services/apiClient', () => ({
  saveSettings: vi.fn(),
  getGitHubAuthStatus: vi.fn(),
  getProviderAvailability: vi.fn(),
  setProviderOptOut: vi.fn(),
}));

const mockedAuth = vi.mocked(apiClient.getGitHubAuthStatus);
const mockedAvailability = vi.mocked(apiClient.getProviderAvailability);
const mockedOptOut = vi.mocked(apiClient.setProviderOptOut);

afterEach(() => { cleanup(); vi.clearAllMocks(); });

function settings(): AppSettings {
  return { basePath: 'F:\\repos', reportPath: 'F:\\out', daysInactive: 30, zipArchive: false, scanDepth: 2 };
}

/** One availability row; the four states are built by overriding the flags. */
function row(overrides: Partial<ProviderAvailability> & { provider: ProviderAvailability['provider'] }): ProviderAvailability {
  return {
    supported: true,
    installed: true,
    optedOut: false,
    available: true,
    authenticated: 'unknown',
    detail: '',
    command: overrides.provider === 'copilot' ? 'gh' : String(overrides.provider),
    ...overrides,
  };
}

function renderSettings() {
  return render(
    <SettingsModal
      isOpen
      onClose={vi.fn()}
      onSave={vi.fn()}
      currentSettings={settings()}
    />
  );
}

beforeEach(() => {
  mockedAuth.mockResolvedValue({
    mode: 'pat', tokenEnvVar: 'GITHUB_TOKEN', tokenSource: 'env', tokenEnvScope: 'User',
    runningAsService: false, hint: '', ghCliPresent: true, liveCheck: null,
  });
});

describe('SettingsModal — agent providers (H38-19b)', () => {
  it('says the section is per-machine and is never committed', async () => {
    mockedAvailability.mockResolvedValue([row({ provider: 'claude' })]);
    renderSettings();
    expect(
      await screen.findByText(
        'Detected on this machine. Nothing here is shared with other installations or committed to the repository.'
      )
    ).toBeInTheDocument();
  });

  it('renders each of the four states with its own sentence', async () => {
    mockedAvailability.mockResolvedValue([
      row({ provider: 'claude' }),
      row({ provider: 'codex', installed: false, available: false }),
      row({ provider: 'copilot', optedOut: true, available: false }),
      row({ provider: 'auto', supported: false, available: false }),
    ]);
    renderSettings();

    expect(await screen.findByText('Ready to run work')).toBeInTheDocument();
    expect(screen.getByText('The codex command was not found on this machine')).toBeInTheDocument();
    expect(screen.getByText('You turned this off here; it will not be selected')).toBeInTheDocument();
    expect(screen.getByText('This version has no adapter for it')).toBeInTheDocument();
  });

  it('names the real CLI, which for copilot is gh and not "copilot"', async () => {
    mockedAvailability.mockResolvedValue([
      row({ provider: 'copilot', installed: false, available: false, command: 'gh' }),
    ]);
    renderSettings();
    expect(await screen.findByText('The gh command was not found on this machine')).toBeInTheDocument();
  });

  it('offers the switch only where there is something to switch', async () => {
    mockedAvailability.mockResolvedValue([
      row({ provider: 'claude' }),
      row({ provider: 'codex', installed: false, available: false }),
      row({ provider: 'copilot', optedOut: true, available: false }),
      row({ provider: 'auto', supported: false, available: false }),
    ]);
    renderSettings();

    await screen.findByText('Ready to run work');
    expect(screen.getByTestId('provider-optout-claude')).toBeInTheDocument();
    expect(screen.getByTestId('provider-optout-copilot')).toBeInTheDocument();
    // Nothing to disable: not installed, or no adapter in this build.
    expect(screen.queryByTestId('provider-optout-codex')).not.toBeInTheDocument();
    expect(screen.queryByTestId('provider-optout-auto')).not.toBeInTheDocument();
  });

  // The portal service runs as LocalSystem and cannot see the operator's User
  // PATH, where per-user installs of claude and codex live. Settings called
  // both "not installed" on a machine where the runner launched them fine.
  it('shows where the runner found the CLI', async () => {
    mockedAvailability.mockResolvedValue([
      row({ provider: 'claude', detectedBy: 'runner', commandPath: 'C:\\Users\\op\\.local\\bin\\claude.exe' }),
    ]);
    renderSettings();
    expect(await screen.findByText('Ready to run work')).toBeInTheDocument();
    expect(screen.getByTestId('provider-path-claude')).toHaveTextContent(
      'Found by the runner at C:\\Users\\op\\.local\\bin\\claude.exe'
    );
  });

  it('says "not checked yet", never "not installed", when no runner has looked', async () => {
    mockedAvailability.mockResolvedValue([
      row({ provider: 'codex', installed: false, available: false, detectedBy: 'unchecked', commandPath: '' }),
    ]);
    renderSettings();
    expect(await screen.findByText('Not checked yet')).toBeInTheDocument();
    expect(screen.getByText('The runner checks for the codex command from your account when it starts')).toBeInTheDocument();
    expect(screen.queryByText('Not installed')).not.toBeInTheDocument();
    expect(screen.queryByTestId('provider-path-codex')).not.toBeInTheDocument();
    // The runner may still select it, so the operator can still switch it off.
    expect(screen.getByTestId('provider-optout-codex')).toBeInTheDocument();
  });

  it('says the runner looked when the runner is the one that missed it', async () => {
    mockedAvailability.mockResolvedValue([
      row({ provider: 'codex', installed: false, available: false, detectedBy: 'runner', commandPath: '' }),
    ]);
    renderSettings();
    expect(await screen.findByText('Not installed')).toBeInTheDocument();
    expect(screen.getByText('The runner looked for the codex command and did not find it')).toBeInTheDocument();
  });

  it('never claims an account works — availability is not authentication', async () => {
    mockedAvailability.mockResolvedValue([row({ provider: 'claude', authenticated: 'unknown' })]);
    renderSettings();
    await screen.findByText('Ready to run work');
    expect(screen.queryByText(/authenticated/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/signed in/i)).not.toBeInTheDocument();
  });

  it('switches a provider off through the installation state, and re-reads it', async () => {
    mockedAvailability.mockResolvedValue([row({ provider: 'claude' })]);
    mockedOptOut.mockResolvedValue(
      row({ provider: 'claude', optedOut: true, available: false })
    );
    renderSettings();

    fireEvent.click(await screen.findByTestId('provider-optout-claude'));

    await waitFor(() => expect(mockedOptOut).toHaveBeenCalledWith('claude', true));
    expect(await screen.findByText('You turned this off here; it will not be selected')).toBeInTheDocument();
  });

  it('keeps the old state on screen when the write fails, and says why', async () => {
    mockedAvailability.mockResolvedValue([row({ provider: 'claude' })]);
    mockedOptOut.mockRejectedValue(new Error('installation state is read-only'));
    renderSettings();

    fireEvent.click(await screen.findByTestId('provider-optout-claude'));

    expect(await screen.findByText(/installation state is read-only/)).toBeInTheDocument();
    // The row must NOT have flipped: an optimistic update here would tell the
    // operator a provider is off while the runner still selects it.
    expect(screen.getByText('Ready to run work')).toBeInTheDocument();
    expect(screen.queryByText('You turned this off here; it will not be selected')).not.toBeInTheDocument();
  });
});
