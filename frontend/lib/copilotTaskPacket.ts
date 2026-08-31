// Lane 0.17 follow-up — normalize a Copilot task packet at the API edge.
//
// The failure this prevents: the backend serializes an empty PowerShell array
// as JSON null under the if-expression enumeration quirk (observed in the
// field: valueContext.rationale was null for repos with no value assessment,
// and the modal's `.length` read took the whole portal down). The backend is
// fixed, but the running service can lag the code — so every array the UI
// iterates is coerced here, at the one choke point every packet passes
// through, and a null object section becomes an empty one.
import { type CopilotTaskPacket } from '../types';

function toArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

export function normalizeCopilotTaskPacket(raw: unknown): CopilotTaskPacket {
  const packet = (raw ?? {}) as CopilotTaskPacket;
  const readme = packet.readmeContext ?? ({} as CopilotTaskPacket['readmeContext']);
  const roadmap = packet.roadmapContext ?? ({} as CopilotTaskPacket['roadmapContext']);
  const value = packet.valueContext ?? ({} as CopilotTaskPacket['valueContext']);
  const selected = packet.selectedRoadmapItem ?? ({} as CopilotTaskPacket['selectedRoadmapItem']);
  const repo = packet.repoContext ?? ({} as CopilotTaskPacket['repoContext']);

  return {
    ...packet,
    repoContext: {
      ...repo,
      blockingReasons: toArray(repo.blockingReasons),
    },
    readmeContext: {
      ...readme,
      summary: readme.summary ?? '',
      headings: toArray(readme.headings),
    },
    roadmapContext: {
      ...roadmap,
      releaseGoal: roadmap.releaseGoal ?? '',
      pendingMilestones: toArray(roadmap.pendingMilestones),
      completedMilestones: toArray(roadmap.completedMilestones),
      acceptanceCriteria: toArray(roadmap.acceptanceCriteria),
      outOfScope: toArray(roadmap.outOfScope),
    },
    selectedRoadmapItem: {
      ...selected,
      text: selected.text ?? '',
      section: selected.section ?? '',
      tags: toArray(selected.tags),
    },
    valueContext: {
      ...value,
      selectedBy: value.selectedBy ?? 'roadmap-order',
      selectedIsTopValueItem: value.selectedIsTopValueItem ?? false,
      rationale: toArray(value.rationale),
    },
    followUpCandidates: toArray(packet.followUpCandidates),
    docFindings: toArray(packet.docFindings),
    constraints: toArray(packet.constraints),
    acceptanceCriteria: toArray(packet.acceptanceCriteria),
    guardrails: toArray(packet.guardrails),
    generatedPrompt: packet.generatedPrompt ?? '',
  };
}
