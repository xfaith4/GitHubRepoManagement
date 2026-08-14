import { describe, expect, it } from 'vitest';
import { classifyFetchFailure } from './fetchFailure';

describe('classifyFetchFailure', () => {
  it('returns null when there is no error', () => {
    expect(classifyFetchFailure(null)).toBeNull();
    expect(classifyFetchFailure(undefined)).toBeNull();
    expect(classifyFetchFailure('   ')).toBeNull();
  });

  it('does not claim a terminal state when repositories are already on screen', () => {
    expect(classifyFetchFailure('Failed to fetch', { hasRepos: true })).toBeNull();
  });

  it('recognises the browser network failure that produced the bare screen', () => {
    const state = classifyFetchFailure('Failed to fetch', { hasRepos: false });
    expect(state?.kind).toBe('backend-unreachable');
    expect(state?.nextStep).toMatch(/Start-App/);
    expect(state?.retryLabel).toBeTruthy();
  });

  it('distinguishes an unconfigured portal from an unreachable backend', () => {
    const unreachable = classifyFetchFailure('NetworkError when attempting to fetch resource');
    const unconfigured = classifyFetchFailure('No repositories are configured for this workspace');
    expect(unreachable?.kind).toBe('backend-unreachable');
    expect(unconfigured?.kind).toBe('not-configured');
    // The whole point: these two need opposite actions.
    expect(unconfigured?.nextStep).not.toBe(unreachable?.nextStep);
    expect(unconfigured?.nextStep).toMatch(/Settings/);
  });

  it('recognises an auth failure', () => {
    expect(classifyFetchFailure('Request failed with 401')?.kind).toBe('auth-required');
    expect(classifyFetchFailure('Unauthorized')?.kind).toBe('auth-required');
  });

  it('falls back to a backend error that still says what to do', () => {
    const state = classifyFetchFailure('Internal server error while enumerating repositories');
    expect(state?.kind).toBe('backend-error');
    expect(state?.nextStep).toBeTruthy();
    expect(state?.retryLabel).toBeTruthy();
  });

  it('never hides the underlying message', () => {
    const raw = 'Failed to fetch';
    expect(classifyFetchFailure(raw)?.detail).toBe(raw);
  });

  it('always names a next step, whatever the classification', () => {
    for (const message of ['Failed to fetch', '403 Forbidden', 'not configured', 'something unexpected']) {
      const state = classifyFetchFailure(message);
      expect(state).not.toBeNull();
      expect(state?.headline.length).toBeGreaterThan(0);
      expect(state?.nextStep.length).toBeGreaterThan(0);
    }
  });
});
