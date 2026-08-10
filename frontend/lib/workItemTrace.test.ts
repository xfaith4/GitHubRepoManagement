import { describe, it, expect } from 'vitest';
import {
  describeTraceStageStatus,
  describeTraceStatus,
  sortTraceStages,
  summarizeTrace,
  traceEvidenceRows,
  traceIdentityPairs,
  type TraceStage,
  type WorkItemTrace,
} from './workItemTrace';

const stage = (
  key: string,
  order: number,
  status: string,
  label = key,
  evidence: Record<string, unknown> | null = null,
): TraceStage => ({ stage: key, label, order, status, evidence });

const trace = (over: Partial<WorkItemTrace> = {}): WorkItemTrace => ({
  traceId: '20260810-000100-abcd1234',
  status: 'active',
  currentStage: 'agentRun',
  completeStageCount: 3,
  stageCount: 7,
  hasGaps: false,
  gaps: [],
  identity: {},
  stages: [
    stage('rank', 1, 'complete', 'Rank'),
    stage('prompt', 2, 'complete', 'Prompt'),
    stage('dispatch', 3, 'complete', 'Dispatch'),
    stage('agentRun', 4, 'pending', 'Agent run'),
    stage('actions', 5, 'pending', 'Actions result'),
    stage('mergeReadiness', 6, 'pending', 'Merge readiness'),
    stage('writeBack', 7, 'pending', 'Roadmap write-back'),
  ],
  ...over,
});

describe('describeTraceStageStatus', () => {
  // The load-bearing distinction: `missing` is a broken link in the chain,
  // `pending` is work the chain has not reached. Rendering them alike is how a
  // stalled loop reads as a young one.
  it('separates a gap from unreached work', () => {
    expect(describeTraceStageStatus('missing').isGap).toBe(true);
    expect(describeTraceStageStatus('missing').severity).toBe('gap');
    expect(describeTraceStageStatus('pending').isGap).toBe(false);
    expect(describeTraceStageStatus('pending').severity).toBe('idle');
  });

  it('maps failed and blocked to the error severity', () => {
    expect(describeTraceStageStatus('failed').severity).toBe('error');
    expect(describeTraceStageStatus('blocked').severity).toBe('error');
  });

  it('falls back rather than throwing on a status it has never seen', () => {
    expect(describeTraceStageStatus('invented-later').label).toBe('Unknown');
  });
});

describe('describeTraceStatus', () => {
  it('names the roll-up states', () => {
    expect(describeTraceStatus('complete').label).toBe('Loop complete');
    expect(describeTraceStatus('blocked').severity).toBe('error');
    expect(describeTraceStatus('').label).toBe('Unknown');
  });
});

describe('sortTraceStages', () => {
  it('restores chain order regardless of payload order', () => {
    const shuffled = [stage('writeBack', 7, 'pending'), stage('rank', 1, 'complete'), stage('actions', 5, 'pending')];
    expect(sortTraceStages(shuffled).map(s => s.stage)).toEqual(['rank', 'actions', 'writeBack']);
  });

  it('does not mutate its input', () => {
    const input = [stage('writeBack', 7, 'pending'), stage('rank', 1, 'complete')];
    sortTraceStages(input);
    expect(input.map(s => s.stage)).toEqual(['writeBack', 'rank']);
  });
});

describe('summarizeTrace', () => {
  it('names where the item is waiting', () => {
    expect(summarizeTrace(trace())).toBe('3/7 stages complete — waiting at agent run.');
  });

  // Progress alone would let "6 of 7 done" hide a stage nothing ever recorded,
  // so a gap displaces the progress narrative rather than sitting beside it.
  it('leads with broken links instead of progress', () => {
    const withGap = trace({ completeStageCount: 6, hasGaps: true, gaps: ['writeBack'], currentStage: 'writeBack' });
    expect(summarizeTrace(withGap)).toBe(
      '6/7 stages complete — 1 broken link in the chain: Roadmap write-back.',
    );
  });

  it('pluralizes multiple broken links', () => {
    const withGaps = trace({ hasGaps: true, gaps: ['rank', 'prompt'] });
    expect(summarizeTrace(withGaps)).toContain('2 broken links in the chain: Rank, Prompt.');
  });

  it('reports a finished loop', () => {
    const done = trace({ status: 'complete', completeStageCount: 7, currentStage: null });
    expect(summarizeTrace(done)).toBe('7/7 stages complete — the item travelled the whole loop.');
  });

  it('handles a missing trace', () => {
    expect(summarizeTrace(null)).toBe('No trace loaded.');
  });
});

describe('traceIdentityPairs', () => {
  it('lists only the ids the chain actually minted', () => {
    const pairs = traceIdentityPairs(
      trace({
        identity: {
          packetId: 'pkt-1',
          packagingRunId: null,
          dispatchRunId: '20260810-000100-abcd1234',
          agentRunId: '',
          branch: 'roadmap-item/add-export',
        },
      }),
    );
    expect(pairs.map(p => p.label)).toEqual(['Packet', 'Dispatch run', 'Branch']);
  });

  it('returns nothing when there is no trace', () => {
    expect(traceIdentityPairs(null)).toEqual([]);
  });
});

describe('traceEvidenceRows', () => {
  it('drops empty values so the facts that exist stand out', () => {
    const rows = traceEvidenceRows(
      stage('rank', 1, 'complete', 'Rank', {
        valueScore: 93,
        valueTier: 'highest',
        valueRationale: ['operator-facing outcome'],
        roadmapOrder: null,
        itemSection: '',
        emptyList: [],
        nested: { ignored: true },
        queued: false,
      }),
    );
    expect(rows).toEqual([
      { label: 'Value score', value: '93' },
      { label: 'Value tier', value: 'highest' },
      { label: 'Value rationale', value: 'operator-facing outcome' },
    ]);
  });

  it('keeps a true boolean, which is a fact, and drops a false one, which is an absence', () => {
    const rows = traceEvidenceRows(stage('dispatch', 3, 'complete', 'Dispatch', { queued: true }));
    expect(rows).toEqual([{ label: 'Queued', value: 'true' }]);
  });

  it('returns nothing for a stage with no evidence', () => {
    expect(traceEvidenceRows(null)).toEqual([]);
    expect(traceEvidenceRows(stage('rank', 1, 'pending'))).toEqual([]);
  });
});
