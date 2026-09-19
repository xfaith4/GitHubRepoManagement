import { afterEach, describe, expect, it, vi } from 'vitest';
import { refreshAllPortfolioAssessment } from './apiClient';

const response = (data: unknown) => new Response(JSON.stringify({ success: true, data }), {
  status: 200, headers: { 'Content-Type': 'application/json' },
});
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });
describe('background full assessment refresh', () => {
  it('reads the published assessment only after the worker completes', async () => {
    const fetch = vi.fn()
      .mockResolvedValueOnce(response({ state: 'completed' }))
      .mockResolvedValueOnce(response({ refreshAccepted: true, entries: [{ repoName: 'old' }] }))
      .mockResolvedValueOnce(response({ state: 'completed' }))
      .mockResolvedValueOnce(response({ entries: [{ repoName: 'new' }], generatedAt: '2026-09-18T00:00:00Z' }));
    vi.stubGlobal('fetch', fetch);
    const result = await refreshAllPortfolioAssessment();
    expect(result.entries[0].repoName).toBe('new');
    expect(String(fetch.mock.calls[3][0])).toContain('includeCuration=true');
  });
  it('reports a failed worker instead of returning the old assessment', async () => {
    const fetch = vi.fn()
      .mockResolvedValueOnce(response({ state: 'completed' }))
      .mockResolvedValueOnce(response({ refreshAccepted: true }))
      .mockResolvedValueOnce(response({ state: 'failed', error: 'Index publication failed' }));
    vi.stubGlobal('fetch', fetch);
    await expect(refreshAllPortfolioAssessment()).rejects.toThrow('Index publication failed');
    expect(fetch).toHaveBeenCalledTimes(3);
  });
  it('does not treat a coalesced differential scan as a full refresh', async () => {
    vi.stubGlobal('fetch', vi.fn()
      .mockResolvedValueOnce(response({ state: 'completed' }))
      .mockResolvedValueOnce(response({ refreshAccepted: false })));
    await expect(refreshAllPortfolioAssessment()).rejects.toThrow('could not start');
  });
});
