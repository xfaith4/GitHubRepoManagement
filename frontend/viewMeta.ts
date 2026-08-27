// Single source of truth for the six primary dashboard views (Release 2.6
// Phase 2). Drives the desktop tab labels, the mobile bottom-nav short labels,
// the per-view purpose subtitle, and the first-visit orientation overlay so
// naming and copy can never drift between those surfaces.

export type ViewKey =
  | 'today'
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
  /**
   * The question this view answers, in the operator's words (Release 3.6 M3).
   * Shown first, because a label names a place while a question names a reason
   * to go there; the Release 2.6 subtitle follows it.
   */
  question: string;
  /** One-line purpose statement shown under the active tab and in the overlay. */
  subtitle: string;
}

export const VIEW_META: ViewMeta[] = [
  {
    key: 'today',
    label: 'Today',
    short: 'Today',
    question: 'What should I do next, and why?',
    subtitle: 'Every repository ranked by what to do first, with the reason and the effort.',
  },
  {
    key: 'repos',
    label: 'Repository Grid',
    short: 'Repos',
    question: 'Where does the portfolio stand right now?',
    subtitle: 'Your main workspace — search, triage, and act on every repository.',
  },
  {
    key: 'insights',
    label: 'Insights',
    short: 'Insights',
    question: 'Is the portfolio getting better over time?',
    subtitle: 'Read-only analytics: portfolio trends, throughput, and documentation health.',
  },
  {
    key: 'operations',
    label: 'Operations',
    short: 'Ops',
    question: 'What exactly is wrong with this repository?',
    subtitle: 'Per-repo detail, prompt refinement, and dispatch preparation.',
  },
  {
    key: 'work-queue',
    label: 'Doc Readiness Queue',
    short: 'Doc Q',
    question: 'Which repositories are ready to be worked?',
    subtitle: 'Repos ranked by README/roadmap readiness — the on-ramp to dispatch.',
  },
  {
    key: 'execution-queue',
    label: 'Copilot Execution Lanes',
    short: 'Lanes',
    question: 'What is running, and is it stuck?',
    subtitle: 'Two-lane console tracking Copilot dispatches in progress.',
  },
  {
    key: 'dependencies',
    label: 'Dependencies',
    short: 'Deps',
    question: 'What does this repository depend on?',
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
