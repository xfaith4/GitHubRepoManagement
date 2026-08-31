// Lane 0.17 follow-up — normalize a Copilot task packet at the API edge.
//
// The failure this pins: the live service serialized an empty PowerShell
// array as JSON null (an if-EXPRESSION enumerates its result, so an empty
// @() collapses to $null). Observed 2026-08-31 on the live portal:
// `valueContext.rationale: null` for repos with no value assessment, and the
// preview modal's `.length` read crashed the whole portal to the app-level
// error boundary. The shape below mirrors the captured live payload.
import { describe, it, expect } from 'vitest';
import { normalizeCopilotTaskPacket } from './copilotTaskPacket';

// The sparse sections of the live test-nextgs packet, verbatim in shape:
// every field a UI `.length`/`.map` touches that arrived null or missing.
const liveSparsePacket = {
  packetVersion: '1.0',
  runId: 'run-field-1',
  createdAt: '2026-08-31T00:00:00Z',
  repoContext: { repoName: 'test-nextgs', roadmapPath: 'F:\\repos\\test-nextgs\\ROADMAP.md', blockingReasons: null },
  readmeContext: { summary: null, headings: null, hasSetupGuidance: false, hasUsageGuidance: false, hasArchitectureGuidance: false },
  roadmapContext: { releaseGoal: null, pendingMilestones: null, completedMilestones: null, acceptanceCriteria: null, outOfScope: null },
  selectedRoadmapItem: { text: 'Store an API key in Settings', section: 'Release 1.0', tags: null },
  followUpCandidates: null,
  docFindings: null,
  valueContext: {
    topValueItemText: null,
    valueTier: null,
    selectedBy: 'roadmap-order',
    selectedIsTopValueItem: false,
    rationale: null, // ← the field crash: "Cannot read properties of null (reading 'length')"
  },
  constraints: null,
  acceptanceCriteria: null,
  guardrails: null,
  generatedPrompt: 'Do the thing.',
};

describe('normalizeCopilotTaskPacket — null arrays from the backend become empty arrays', () => {
  it('coerces every UI-iterated array, including the field-observed rationale: null', () => {
    const packet = normalizeCopilotTaskPacket(liveSparsePacket);

    expect(packet.valueContext.rationale).toEqual([]);
    expect(packet.readmeContext.headings).toEqual([]);
    expect(packet.roadmapContext.pendingMilestones).toEqual([]);
    expect(packet.roadmapContext.completedMilestones).toEqual([]);
    expect(packet.roadmapContext.acceptanceCriteria).toEqual([]);
    expect(packet.roadmapContext.outOfScope).toEqual([]);
    expect(packet.selectedRoadmapItem.tags).toEqual([]);
    expect(packet.repoContext.blockingReasons).toEqual([]);
    expect(packet.followUpCandidates).toEqual([]);
    expect(packet.docFindings).toEqual([]);
    expect(packet.constraints).toEqual([]);
    expect(packet.acceptanceCriteria).toEqual([]);
    expect(packet.guardrails).toEqual([]);
  });

  it('tolerates whole sections missing', () => {
    const packet = normalizeCopilotTaskPacket({ runId: 'x' });
    expect(packet.valueContext.rationale).toEqual([]);
    expect(packet.readmeContext.headings).toEqual([]);
    expect(packet.roadmapContext.pendingMilestones).toEqual([]);
    expect(packet.selectedRoadmapItem.text).toBe('');
    expect(packet.generatedPrompt).toBe('');
  });

  it('preserves populated data untouched', () => {
    const packet = normalizeCopilotTaskPacket({
      ...liveSparsePacket,
      valueContext: { ...liveSparsePacket.valueContext, rationale: ['high leverage', 'small surface'] },
      guardrails: [{ rule: 'No force-push' }],
      acceptanceCriteria: ['It works'],
    });
    expect(packet.valueContext.rationale).toEqual(['high leverage', 'small surface']);
    expect(packet.guardrails).toEqual([{ rule: 'No force-push' }]);
    expect(packet.acceptanceCriteria).toEqual(['It works']);
    expect(packet.selectedRoadmapItem.text).toBe('Store an API key in Settings');
  });
});
