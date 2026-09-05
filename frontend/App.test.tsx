// @vitest-environment jsdom
//
// The auth gate and the first data load.
//
// A gated host answers /api/status with 401 until the browser holds a session.
// The first load used to fire on mount, before /api/auth/status had resolved,
// so on a protected portal the refusal was stored as the page error, survived
// the login, and greeted the operator until they pressed Retry. These tests
// pin the order: no data request before the auth check resolves, and after a
// login the dashboard opens on data rather than on the pre-login refusal.
import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, screen, fireEvent, cleanup, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import App from './App';
import * as apiClient from './services/apiClient';

vi.mock('./services/apiClient', () => ({
  getAuthStatus: vi.fn(),
  getStatus: vi.fn(),
  getSetupStatus: vi.fn(),
  getGithubRepoInsights: vi.fn(),
  login: vi.fn(),
  logout: vi.fn(),
  setApiKey: vi.fn(),
}));

// The shell around the data is not under test. Stubs keep the assertions on
// what App itself decides: when to load, and which error it hands down.
vi.mock('./components/Dashboard', () => ({
  default: ({ error, dataSource, onConnectGitHub }: { error: string | null; dataSource: { source: string }; onConnectGitHub: (user: string) => Promise<void> }) => (
    <div data-testid="dashboard">{error ?? 'no error'}<span data-testid="active-source">{dataSource?.source ?? 'local'}</span><button onClick={() => void onConnectGitHub('fixture')}>Connect fixture</button></div>
  ),
}));
vi.mock('./components/SetupWizard', () => ({ default: () => null }));
vi.mock('./components/AgentActivityIndicator', () => ({ default: () => null }));
vi.mock('./components/RunnerHealthIndicator', () => ({ default: () => null }));
vi.mock('./components/BuildStampIndicator', () => ({ default: () => null }));
vi.mock('./components/TransportSecurityIndicator', () => ({ default: () => null }));
vi.mock('./components/MobileRepoHealth', () => ({ default: () => null }));
vi.mock('./components/OrientationOverlay', () => ({ default: () => null, hasSeenOrientation: () => true }));

const mockedAuthStatus = vi.mocked(apiClient.getAuthStatus);
const mockedGetStatus = vi.mocked(apiClient.getStatus);
const mockedSetupStatus = vi.mocked(apiClient.getSetupStatus);
const mockedLogin = vi.mocked(apiClient.login);

const REFUSAL = 'Unauthorized: log in at /api/auth/login, or send an API key as `Authorization: Bearer <key>` or `X-Api-Key: <key>`.';

function authStatus(overrides: Partial<apiClient.AuthStatus> = {}): apiClient.AuthStatus {
  return {
    authRequired: true,
    authEnforced: true,
    gateEnabled: true,
    loginConfigured: true,
    authenticated: false,
    method: null,
    isLoopbackBind: true,
    ...overrides,
  };
}

const LOCAL_DATA: Awaited<ReturnType<typeof apiClient.getStatus>> = {
  repos: [],
  source: 'local',
  workspacePath: 'F:\\Development',
  configuredGithubUser: null,
  repoCount: 0,
  fromCache: true,
};

beforeEach(() => {
  mockedSetupStatus.mockResolvedValue({ needsSetup: false } as Awaited<ReturnType<typeof apiClient.getSetupStatus>>);
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

async function signIn(password = 'hunter2') {
  fireEvent.change(screen.getByLabelText('Password'), { target: { value: password } });
  fireEvent.click(screen.getByRole('button', { name: 'Sign in' }));
}

describe('App auth gate and first load', () => {
  it('holds the first data request until the login succeeds, so the refusal never becomes the page error', async () => {
    // The host as the browser sees it: /api/status refuses until a session is
    // held, and the login is what grants one.
    let sessionHeld = false;
    mockedAuthStatus.mockImplementation(async () =>
      authStatus({ authenticated: sessionHeld, method: sessionHeld ? 'session' : null }));
    mockedGetStatus.mockImplementation(async () => {
      if (!sessionHeld) throw new Error(REFUSAL);
      return LOCAL_DATA;
    });
    mockedLogin.mockImplementation(async () => { sessionHeld = true; });

    render(<App />);

    await screen.findByTestId('login-form');
    expect(mockedGetStatus).not.toHaveBeenCalled();

    await signIn();

    const dashboard = await screen.findByTestId('dashboard');
    await waitFor(() => expect(mockedGetStatus).toHaveBeenCalled());
    expect(mockedGetStatus.mock.calls[0][0]).toMatchObject({ stale: true });
    expect(dashboard).toHaveTextContent('no error');
    expect(dashboard).not.toHaveTextContent(REFUSAL);
  });

  it('loads immediately on an open host', async () => {
    mockedAuthStatus.mockResolvedValue(authStatus({ gateEnabled: false, authRequired: false, authEnforced: false, loginConfigured: false }));
    mockedGetStatus.mockResolvedValue(LOCAL_DATA);

    render(<App />);

    await screen.findByTestId('dashboard');
    await waitFor(() => expect(mockedGetStatus).toHaveBeenCalled());
    expect(screen.queryByTestId('login-form')).not.toBeInTheDocument();
  });

  it('still loads when the auth status route is unreachable, surfacing any refusal in context', async () => {
    mockedAuthStatus.mockRejectedValue(new Error('HTTP 404'));
    mockedGetStatus.mockResolvedValue(LOCAL_DATA);

    render(<App />);

    await screen.findByTestId('dashboard');
    await waitFor(() => expect(mockedGetStatus).toHaveBeenCalled());
  });
});

it('connecting GitHub preserves the selected source until the operator switches it', async () => {
  mockedAuthStatus.mockResolvedValue(authStatus({ gateEnabled: false, authenticated: true }));
  mockedGetStatus.mockResolvedValue(LOCAL_DATA);
  vi.mocked(apiClient.getGithubRepoInsights).mockResolvedValue({ repos: [], source: 'github', username: 'fixture', totalRepos: 0, fetchedRepos: 0, rateLimit: null } as Awaited<ReturnType<typeof apiClient.getGithubRepoInsights>>);
  render(<App />);
  await screen.findByTestId('dashboard');
  fireEvent.click(screen.getByRole('button', { name: 'Connect fixture' }));
  await waitFor(() => expect(screen.getByRole('button', { name: 'GitHub' })).toBeEnabled());
  expect(screen.getByTestId('active-source')).toHaveTextContent('local');
  fireEvent.click(screen.getByRole('button', { name: 'GitHub' }));
  expect(screen.getByTestId('active-source')).toHaveTextContent('github');
});
