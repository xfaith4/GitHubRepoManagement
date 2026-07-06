// Single source of truth for the six primary dashboard views (Release 2.6
// Phase 2). Drives the desktop tab labels, the mobile bottom-nav short labels,
// the per-view purpose subtitle, and the first-visit orientation overlay so
// naming and copy can never drift between those surfaces.

export type ViewKey =
  | 'repos'
  | 'insights'
  | 'operations'
  | 'work-queue'
  | 'execution-queue'
  | 'dependencies';

export interface ViewMeta {
  key: ViewKey;
  /** Desktop tab label. */
  label: string;
  /** Compact mobile bottom-nav label. */
  short: string;
  /** One-line purpose statement shown under the active tab and in the overlay. */
  subtitle: string;
}

export const VIEW_META: ViewMeta[] = [
  {
    key: 'repos',
    label: 'Repository Grid',
    short: 'Repos',
    subtitle: 'Your main workspace — search, triage, and act on every repository.',
  },
  {
    key: 'insights',
    label: 'Insights',
    short: 'Insights',
    subtitle: 'Read-only analytics: portfolio trends, throughput, and documentation health.',
  },
  {
    key: 'operations',
    label: 'Operations',
    short: 'Ops',
    subtitle: 'Per-repo detail, prompt refinement, and dispatch preparation.',
  },
  {
    key: 'work-queue',
    label: 'Doc Readiness Queue',
    short: 'Doc Q',
    subtitle: 'Repos ranked by README/roadmap readiness — the on-ramp to dispatch.',
  },
  {
    key: 'execution-queue',
    label: 'Copilot Execution Lanes',
    short: 'Lanes',
    subtitle: 'Two-lane console tracking Copilot dispatches in progress.',
  },
  {
    key: 'dependencies',
    label: 'Dependencies',
    short: 'Deps',
    subtitle: 'Cross-repo references detected across portfolio roadmaps.',
  },
];

export const VIEW_META_BY_KEY: Record<ViewKey, ViewMeta> = VIEW_META.reduce(
  (acc, meta) => {
    acc[meta.key] = meta;
    return acc;
  },
  {} as Record<ViewKey, ViewMeta>,
);
