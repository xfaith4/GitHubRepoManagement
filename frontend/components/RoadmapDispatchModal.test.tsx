// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import RoadmapDispatchModal from './RoadmapDispatchModal';
import * as apiClient from '../services/apiClient';

vi.mock('../services/apiClient', () => ({
  checkRoadmapDispatch: vi.fn(),
  executeRoadmapDispatch: vi.fn(),
  applyRoadmapRepair: vi.fn(),
  getRunnerPresence: vi.fn(),
}));

const mockedCheck = vi.mocked(apiClient.checkRoadmapDispatch);
const mockedPresence = vi.mocked(apiClient.getRunnerPresence);

afterEach(() => { cleanup(); vi.clearAllMocks(); });

describe('RoadmapDispatchModal execution-contract readiness', () => {
  it('shows the same named verdict that refused dispatch, not a private L3 rule', async () => {
    mockedPresence.mockResolvedValue(null);
    mockedCheck.mockResolvedValue({
      repoName: 'fixture',
      maturityLevel: 'L2-Structured',
      maturityScore: 58,
      dispatchReady: false,
      executionContract: {
        schemaVersion: '1.0',
        model: 'execution-contract-sufficiency',
        sufficient: false,
        code: 'execution-contract-verification-missing',
        explanation: 'Name an exact command, script, or API request in the validation plan.',
        maturityLevel: 'L2-Structured',
        repoType: 'node',
        checks: [
          { name: 'scope', passed: true, code: 'execution-contract-scope-missing', explanation: 'Scope is present.' },
          { name: 'acceptance', passed: true, code: 'execution-contract-acceptance-missing', explanation: 'Acceptance is present.' },
          { name: 'verification', passed: false, code: 'execution-contract-verification-missing', explanation: 'Name an exact command, script, or API request in the validation plan.' },
          { name: 'sizing', passed: true, code: 'execution-contract-sizing-missing', explanation: 'Task is bounded.' },
        ],
      },
      repairPreview: null,
      releasePacket: null,
    });

    render(<RoadmapDispatchModal isOpen repoName="fixture" onClose={vi.fn()} />);

    const verdict = await screen.findByTestId('execution-contract-verdict');
    expect(verdict).toHaveTextContent('Execution contract needs repair');
    expect(verdict).toHaveTextContent('Name an exact command, script, or API request');
    expect(verdict).not.toHaveTextContent('Dispatch requires L3');
  });
});

