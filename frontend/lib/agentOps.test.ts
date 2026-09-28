// Agent Ops view model (2026-09-27).
//
// The failure these prevent: a board that shows the wrong state for a run,
// orders the operator's decisions arbitrarily, or invents a figure the host
// never sent. Everything here is pure, so a host is never needed to prove it.
import { describe, it, expect } from 'vitest';
import {
  DELIVERY_STATES,
  anchorState,
  buildActivityFeed,
  buildRepoProgress,
  countByStage,
  countOperatorActions,
  deriveDeliveryState,
  deriveOperatorActions,
  describeHeldBanner,
  describeStopSummary,
  formatAgo,
  selectCurrentPhase,
  selectInFlight,
  selectInterruptible,
  selectNextUp,
  selectRecentlyCompleted,
  stageOfState,
  stateIndex,
  toAgentOpsRun,
} from './agentOps';
import type { AgentRun, ExecutionLaneEntry, RoadmapEntry } from '../types';
import type { PackagedItem } from './packagedItems';
import type { RunnerPresencePayload } from './runnerPresence';

const NOW = Date.parse('2026-09-27T12:00:00Z');
const minutesAgo = (m: number) => new Date(NOW - m * 60_000).toISOString();

function run(overrides: Partial<AgentRun> = {}): AgentRun {
  return {
    runId: overrides.runId ?? 'run-1',
    repoName: 'alpha',
    providerTool: 'claude',
    status: 'active',
    selectedTaskText: 'Do the thing',
    createdAt: minutesAgo(30),
    updatedAt: minutesAgo(5),
    ...overrides,
  } as AgentRun;
}

function roadmap(repoName: string, done: number, pending: number, title = `${repoName} release`): RoadmapEntry {
  return {
    repoName,
    repoPath: `C:/repos/${repoName}`,
    roadmapPath: 'ROADMAP.md',
    lastModified: minutesAgo(60),
    sizeBytes: 100,
    completedCount: done,
    pendingCount: pending,
    activeRelease: { releaseTitle: title },
    activePhasePlan: { phaseName: 'Phase A' },
    nextPendingItem: { text: 'Next item', section: 'Phase A' },
  } as RoadmapEntry;
}

describe('deriveDeliveryState — the host field wins, the legacy status is only a fallback', () => {
  it('reads deliveryState when the host sends it, whatever the legacy status says', () => {
    expect(deriveDeliveryState({ deliveryState: 'READY_FOR_OPERATOR', status: 'active' })).toBe('READY_FOR_OPERATOR');
    expect(deriveDeliveryState({ deliveryState: 'stopped', status: 'active' })).toBe('STOPPED');
  });

  it('maps the legacy status only when no delivery state arrived', () => {
    expect(deriveDeliveryState({ deliveryState: null, status: 'active' })).toBe('AGENT_RUNNING');
    expect(deriveDeliveryState({ status: 'awaiting-review' } as unknown as AgentRun)).toBe('READY_FOR_OPERATOR');
    expect(deriveDeliveryState({ status: 'failed' } as unknown as AgentRun)).toBe('CI_FAILED');
    expect(deriveDeliveryState({ status: 'blocked' } as unknown as AgentRun)).toBe('CAPACITY_WAIT');
  });

  it('defaults to QUEUED rather than inventing progress', () => {
    expect(deriveDeliveryState({ status: 'something-new' } as unknown as AgentRun)).toBe('QUEUED');
  });
});

describe('the 20-state strip', () => {
  it('has exactly twenty states from DISCOVERED to COMPLETE', () => {
    expect(DELIVERY_STATES).toHaveLength(20);
    expect(DELIVERY_STATES[0]).toBe('DISCOVERED');
    expect(DELIVERY_STATES[19]).toBe('COMPLETE');
  });

  it('anchors off-path states where they sit on the path', () => {
    expect(anchorState('CAPACITY_WAIT')).toBe('CAPACITY_EVALUATING');
    expect(anchorState('CI_FAILED')).toBe('CI_PENDING');
    expect(stateIndex('CI_FAILED')).toBe(DELIVERY_STATES.indexOf('CI_PENDING'));
    expect(stateIndex('CANCELLED')).toBe(-1);
  });

  it('places a STOPPED run where it was interrupted, and in that stage', () => {
    expect(stateIndex('STOPPED', 'LOCAL_VERIFYING')).toBe(DELIVERY_STATES.indexOf('LOCAL_VERIFYING'));
    expect(stageOfState('STOPPED', 'CI_PENDING').key).toBe('ci');
    expect(stageOfState('STOPPED', null).key).toBe('agent');
  });
});

describe('toAgentOpsRun', () => {
  it('labels a stopped run with where it was, and flags a remote one', () => {
    const local = toAgentOpsRun(run({ deliveryState: 'STOPPED', stoppedFrom: 'AGENT_RUNNING' }));
    expect(local.stateLabel).toBe('STOPPED · AGENT_RUNNING');
    expect(local.tone).toBe('bad');
    const remote = toAgentOpsRun(run({ deliveryState: 'STOPPED', stoppedFrom: 'PROVIDER_SELECTED', stoppedRemote: true, providerTool: 'copilot' }));
    expect(remote.stateLabel).toBe('STOPPED · PROVIDER_SELECTED · remote');
    expect(remote.remote).toBe(true);
    expect(remote.providerLabel).toBe('Copilot Agent');
  });

  it('takes the attempt from the summary before guessing from retries', () => {
    expect(toAgentOpsRun(run({ attempt: 3 })).attempt).toBe(3);
    expect(toAgentOpsRun(run({ metrics: { retries: 1 } })).attempt).toBe(2);
    expect(toAgentOpsRun(run()).attempt).toBe(1);
  });

  it('names the verified head as the sha an approval would bind to', () => {
    expect(toAgentOpsRun(run({ verifiedHeadSha: 'abc1234567', prHeadSha: 'zzz' })).sha).toBe('abc1234567');
    expect(toAgentOpsRun(run({ prHeadSha: 'zzz9999' })).sha).toBe('zzz9999');
  });
});

describe('selectInFlight / selectRecentlyCompleted / selectInterruptible', () => {
  const rows = [
    run({ runId: 'queued', deliveryState: 'QUEUED' }),
    run({ runId: 'agent', deliveryState: 'AGENT_RUNNING' }),
    run({ runId: 'ci', deliveryState: 'CI_PENDING', repoName: 'bravo' }),
    run({ runId: 'wait', deliveryState: 'CAPACITY_WAIT' }),
    run({ runId: 'op', deliveryState: 'READY_FOR_OPERATOR' }),
    run({ runId: 'stopped', deliveryState: 'STOPPED', stoppedFrom: 'AGENT_RUNNING' }),
    run({ runId: 'done', deliveryState: 'COMPLETE', updatedAt: minutesAgo(1) }),
    run({ runId: 'merged', deliveryState: 'MERGED', updatedAt: minutesAgo(2) }),
    run({ runId: 'cancelled', deliveryState: 'CANCELLED', updatedAt: minutesAgo(3) }),
  ].map(toAgentOpsRun);

  it('lists scheduling through the operator gate plus stopped runs, furthest along first', () => {
    const ids = selectInFlight(rows).map(r => r.id);
    expect(ids).toEqual(['op', 'ci', 'agent', 'stopped', 'wait']);
  });

  it('lists what landed, newest first, capped', () => {
    expect(selectRecentlyCompleted(rows).map(r => r.id)).toEqual(['done', 'merged', 'cancelled']);
    expect(selectRecentlyCompleted(rows, 2).map(r => r.id)).toEqual(['done', 'merged']);
  });

  it('interrupts scheduling, agent work and CI, never a wait, a stopped run or the operator gate', () => {
    expect(selectInterruptible(rows).map(r => r.id).sort()).toEqual(['agent', 'ci']);
  });
});

describe('deriveOperatorActions — the fixed order and the honest buttons', () => {
  const runner: RunnerPresencePayload = { state: 'absent', stoppedByOperator: true, stoppedAt: minutesAgo(3), stopReason: 'bad batch', stopInterruptedCount: 2 };
  const rows = [
    run({ runId: 'ci', deliveryState: 'CI_FAILED', prNumber: 8, attempt: 1 }),
    run({ runId: 'approve', deliveryState: 'READY_FOR_OPERATOR', prNumber: 22, verifiedHeadSha: '9f3c2a1ff' }),
    run({ runId: 'merge', deliveryState: 'OPERATOR_APPROVED', prNumber: 212, repoId: 'repo:alpha', operatorApproval: { sha: 'e44a9b0', at: minutesAgo(8), actor: 'ben' } }),
    run({ runId: 'noop', deliveryState: 'AGENT_RUNNING' }),
  ].map(toAgentOpsRun);
  const packages: PackagedItem[] = [
    { packetId: 'pk-88', status: 'pending-approval', repoName: 'auditor', packagedAt: minutesAgo(35), packet: { itemText: 'Rule: detect orphaned users', valueScore: 82, maturityLevel: 'L3' } } as PackagedItem,
    { packetId: 'pk-old', status: 'dispatched', repoName: 'auditor', packet: { itemText: 'already gone' } } as PackagedItem,
  ];

  it('orders runner held → approve → merge → CI failed → package', () => {
    const actions = deriveOperatorActions({ rows, packages, runner, nowMs: NOW });
    expect(actions.map(a => a.kind)).toEqual(['runner-held', 'approve-sha', 'merge', 'ci-failed', 'package-approval']);
    expect(actions[0].detail).toContain('2 runs interrupted 3m ago');
    expect(actions[0].detail).toContain('bad batch');
  });

  it('binds approval to the verified sha and merge to the repo id', () => {
    const actions = deriveOperatorActions({ rows, packages: [], runner: null, nowMs: NOW });
    const approve = actions.find(a => a.kind === 'approve-sha');
    expect(approve?.primary.label).toBe('Approve 9f3c2a1');
    expect(approve?.primary.op).toEqual({ type: 'approve', runId: 'approve', sha: '9f3c2a1ff' });
    expect(approve?.primary.consequence).toBe(true);
    expect(approve?.secondary?.consequence).toBe(false);
    const merge = actions.find(a => a.kind === 'merge');
    expect(merge?.primary.op).toEqual({ type: 'merge', repoId: 'repo:alpha', runId: 'merge' });
    expect(merge?.detail).toContain('irreversible');
  });

  it('offers re-evaluation, not a fake approval, when no verified commit exists', () => {
    const actions = deriveOperatorActions({ rows: [toAgentOpsRun(run({ deliveryState: 'READY_FOR_OPERATOR' }))], packages: [], runner: null, nowMs: NOW });
    expect(actions[0].primary.op.type).toBe('refresh');
    expect(actions[0].detail).toContain('No verified commit');
  });

  it('counts only pending packages, and the badge count matches the list', () => {
    const actions = deriveOperatorActions({ rows, packages, runner, nowMs: NOW });
    expect(actions.filter(a => a.kind === 'package-approval')).toHaveLength(1);
    expect(countOperatorActions(rows.map(r => r.run), packages, runner)).toBe(actions.length);
  });

  it('is empty when nothing waits on the operator', () => {
    expect(deriveOperatorActions({ rows: [rows[3]], packages: [], runner: { state: 'present', present: true }, nowMs: NOW })).toEqual([]);
  });
});

describe('buildActivityFeed', () => {
  it('flags failures, interrupts, stops and limits with the red dot and sorts newest first', () => {
    const rows = [
      toAgentOpsRun(run({ runId: 'a', deliveryState: 'CI_FAILED', updatedAt: minutesAgo(1), actions: { status: 'completed', conclusion: 'failure', workflowName: 'smoke', observedAt: minutesAgo(2) } })),
      toAgentOpsRun(run({ runId: 'b', deliveryState: 'STOPPED', stoppedFrom: 'AGENT_RUNNING', updatedAt: minutesAgo(4) })),
      toAgentOpsRun(run({ runId: 'c', deliveryState: 'AGENT_RUNNING', updatedAt: minutesAgo(3), metrics: { agentStartedAt: minutesAgo(10) } })),
    ];
    const feed = buildActivityFeed(rows, { state: 'absent', stoppedByOperator: true, stoppedAt: minutesAgo(4), stopInterruptedCount: 1 });
    expect(feed[0].message).toBe('CI_FAILED');
    expect(feed[0].bad).toBe(true);
    expect(feed.find(e => e.message.startsWith('Interrupted by All work stop'))?.bad).toBe(true);
    expect(feed.find(e => e.message.startsWith('ALL WORK STOP'))?.repo).toBe('operator');
    expect(feed.find(e => e.message.startsWith('Agent started'))?.bad).toBe(false);
    for (let i = 1; i < feed.length; i++) expect(feed[i - 1].atMs).toBeGreaterThanOrEqual(feed[i].atMs);
  });

  it('caps the feed', () => {
    const rows = Array.from({ length: 20 }, (_, i) => toAgentOpsRun(run({ runId: `r${i}`, updatedAt: minutesAgo(i) })));
    expect(buildActivityFeed(rows, null)).toHaveLength(14);
    expect(buildActivityFeed(rows, null, 3)).toHaveLength(3);
  });
});

describe('roll-ups', () => {
  it('counts runs per stage and ages COMPLETE out of the landed column after a day', () => {
    const rows = [
      run({ runId: 'a', deliveryState: 'AGENT_RUNNING' }),
      run({ runId: 'b', deliveryState: 'COMPLETE', updatedAt: minutesAgo(10) }),
      run({ runId: 'c', deliveryState: 'COMPLETE', updatedAt: minutesAgo(48 * 60) }),
      run({ runId: 'd', deliveryState: 'MERGED', updatedAt: minutesAgo(48 * 60) }),
    ].map(toAgentOpsRun);
    const counts = Object.fromEntries(countByStage(rows, NOW).map(s => [s.key, s.count]));
    expect(counts.agent).toBe(1);
    expect(counts.landed).toBe(2);
  });

  it('builds repo progress from roadmap counts and in-flight runs, active repos first', () => {
    const rows = [run({ runId: 'a', repoName: 'bravo', deliveryState: 'AGENT_RUNNING' })].map(toAgentOpsRun);
    const progress = buildRepoProgress([roadmap('alpha', 14, 8), roadmap('bravo', 2, 8), roadmap('empty', 0, 0)], rows);
    expect(progress.map(p => p.repo)).toEqual(['bravo', 'alpha']);
    expect(progress[0]).toMatchObject({ done: 2, total: 10, active: 1, phase: 'bravo release' });
  });

  it('leads with the repository that has the most runs in flight, and reports its counts', () => {
    const entries = [roadmap('alpha', 14, 8), roadmap('bravo', 2, 8)];
    const rows = [
      run({ runId: 'a', repoName: 'bravo', deliveryState: 'AGENT_RUNNING' }),
      run({ runId: 'b', repoName: 'bravo', deliveryState: 'CI_PENDING' }),
      run({ runId: 'c', repoName: 'alpha', deliveryState: 'AGENT_RUNNING' }),
    ].map(toAgentOpsRun);
    const phase = selectCurrentPhase(entries, rows);
    expect(phase).toMatchObject({ repo: 'bravo', title: 'bravo release', done: 2, total: 10, pct: 20, phaseName: 'Phase A', nextItem: 'Next item' });
    expect(selectCurrentPhase([], rows)).toBeNull();
    expect(selectCurrentPhase(entries, [])?.repo).toBe('alpha');
  });

  it('ranks the queue by score and skips entries already running', () => {
    const entries = [
      { repoName: 'a', executionState: 'ready', priorityScore: 40, currentTaskText: 'low' },
      { repoName: 'b', executionState: 'ready', priorityScore: 90, currentTaskText: 'high' },
      { repoName: 'c', executionState: 'running', priorityScore: 99, currentTaskText: 'busy' },
    ] as ExecutionLaneEntry[];
    expect(selectNextUp(entries).map(n => `${n.rank}:${n.repo}`)).toEqual(['1:b', '2:a']);
  });
});

describe('copy', () => {
  it('formats ages without going negative', () => {
    expect(formatAgo(NOW - 12_000, NOW)).toBe('12s ago');
    expect(formatAgo(NOW - 4 * 60_000, NOW)).toBe('4m ago');
    expect(formatAgo(NOW + 60_000, NOW)).toBe('0s ago');
    expect(formatAgo(null, NOW)).toBe('—');
  });

  it('writes the stop summary in the operator\'s terms, singular and plural', () => {
    const rows = [run({ runId: 'a', repoName: 'alpha', deliveryState: 'AGENT_RUNNING' }), run({ runId: 'b', repoName: 'bravo', deliveryState: 'CI_PENDING' })].map(toAgentOpsRun);
    expect(describeStopSummary(rows)).toBe('2 runs are mid-flight (alpha, bravo). They will be interrupted now.');
    expect(describeStopSummary(rows.slice(0, 1))).toBe('1 run is mid-flight (alpha). It will be interrupted now.');
    expect(describeStopSummary([])).toBe('0 runs are mid-flight (none). They will be interrupted now.');
  });

  it('writes the held banner from the hold record', () => {
    expect(describeHeldBanner({ stoppedByOperator: true, stoppedAt: minutesAgo(2), stopReason: 'bad prompt', stopInterruptedCount: 3 }, NOW))
      .toBe('All work stopped 2m ago: 3 runs interrupted · “bad prompt”. Runners are held, so no new work is claimed.');
  });
});
