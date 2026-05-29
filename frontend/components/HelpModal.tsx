import React, { useMemo, useState } from 'react';
import { HelpIcon } from './icons';

interface HelpModalProps {
  isOpen: boolean;
  onClose: () => void;
}

type HelpTabId = 'start' | 'main-window' | 'popups' | 'workflows' | 'tips';

interface HelpTab {
  id: HelpTabId;
  label: string;
  kicker: string;
  title: string;
  intro: string;
}

const tabs: HelpTab[] = [
  {
    id: 'start',
    label: 'Start Here',
    kicker: 'Purpose',
    title: 'GitHub Repo Manager helps you assess, rank, dispatch, and report work across many repositories.',
    intro: 'Use it to scan your workspace, classify every repository, fix blockers, rank pending roadmap work, refine dispatch packets, and report portfolio progress from one place.',
  },
  {
    id: 'main-window',
    label: 'Main Window',
    kicker: 'Tour',
    title: 'The main window is your portfolio dashboard.',
    intro: 'Read it from top to bottom: connection status, workspace summary, action buttons, then the working table or queue.',
  },
  {
    id: 'popups',
    label: 'Popups',
    kicker: 'Screens',
    title: 'Popups are used for focused work.',
    intro: 'Each popup handles one job, such as settings, roadmap review, README generation, or operation progress.',
  },
  {
    id: 'workflows',
    label: 'Workflows',
    kicker: 'How To',
    title: 'Common workflows follow a simple review-first pattern.',
    intro: 'Most write actions first show a preview. Review the suggested content, make edits if the screen allows it, then apply or create.',
  },
  {
    id: 'tips',
    label: 'Tips',
    kicker: 'Guidance',
    title: 'Use the app as an operating console, not just a repo list.',
    intro: 'Scan first, sort or filter next, then work from the highest-priority repos instead of opening every repository by hand.',
  },
];

const mainWindowSections = [
  {
    title: 'Status Strip',
    body: 'Shows backend connection and auto-scan timing. If the backend is offline, refresh and write actions will not work.',
  },
  {
    title: 'Scan Progress',
    body: 'Appears while the app is scanning repositories. Open View progress when you want to see what is happening.',
  },
  {
    title: 'Workspace Notice',
    body: 'Confirms whether you are viewing local repositories or GitHub API results. Use Settings if the local path or scan depth is wrong.',
  },
  {
    title: 'Summary Numbers',
    body: 'Shows totals like repository count, dirty repos, sync state, stale repos, and recent commits. Use this area for a quick health check.',
  },
  {
    title: 'Action Bar',
    body: 'Run common actions: Pull, Fetch, Report, Doc Review, Roadmap Scan, Help, API Docs, Refresh, and Settings. Report writes a plain-language Collection Status Report for the current portfolio slice.',
  },
  {
    title: 'Repository Grid',
    body: 'Lists scanned repositories. Select repos for targeted actions, inspect dirty status, open artifacts, and view existing roadmaps.',
  },
  {
    title: 'Operations',
    body: 'Shows one repo at a time with indexed lifecycle, GitHub, dirty-worktree, and recommended-action detail. Use it when you want to inspect a specific repo before previewing task work.',
  },
  {
    title: 'Work Queue',
    body: 'Shows which repos are ready, blocked, missing docs, or missing roadmaps. This is the best place to decide what to fix next.',
  },
  {
    title: 'Execution Queue',
    body: 'Tracks repos that are ready for dispatched work and shows active lanes, queue candidates, and recent execution history.',
  },
  {
    title: 'Dependencies',
    body: 'Shows roadmap references between repositories so you can see when one repo depends on another.',
  },
];

const popupSections = [
  {
    title: 'Settings',
    body: 'Choose the local workspace path, scan depth, stale threshold, and GitHub user settings.',
  },
  {
    title: 'Operation Log',
    body: 'Shows progress and results for scans, pulls, fetches, reports, audits, and other running actions.',
  },
  {
    title: 'Doc Review',
    body: 'Builds a documentation inventory and optional work queue for repositories that need documentation attention.',
  },
  {
    title: 'ROADMAP Viewer',
    body: 'Displays an existing ROADMAP file and lets you preview or start a roadmap-based Copilot task. It is not the create-roadmap screen.',
  },
  {
    title: 'Repo Evaluation',
    body: 'Use this when a repo has no roadmap or needs a stronger one. Evaluation highlights hardening, modernization, security, and user-value opportunities, then proposes roadmap-ready tasks.',
  },
  {
    title: 'Roadmap Audit',
    body: 'Shows roadmap maturity, score, findings, and why a roadmap is or is not ready for orchestration.',
  },
  {
    title: 'Roadmap Repair',
    body: 'Shows a proposed rewrite for a weak roadmap. Review the diff before applying changes.',
  },
  {
    title: 'Roadmap Lint',
    body: 'Shows formatting and structure issues that could make a roadmap harder to parse or dispatch.',
  },
  {
    title: 'README Tools',
    body: 'Generate a missing README or standardize an existing one. Review suggested content before applying it.',
  },
  {
    title: 'Git Status',
    body: 'Opens when a repo has local changes. Use it to inspect changed files before deciding what to do.',
  },
  {
    title: 'API Docs',
    body: 'Reference for backend endpoints. Most end users will not need this during normal repo management.',
  },
];

const workflows = [
  {
    title: 'Start a normal session',
    steps: [
      'Open the app and confirm Backend is Online.',
      'Check the workspace notice to confirm the app is scanning the right folder.',
      'Review the Portfolio Mission summary for lifecycle and blocker counts.',
      'Use Repository Grid for general repo review, Operations for one-repo detail, or Work Queue for roadmap and documentation work.',
    ],
  },
  {
    title: 'Run the portfolio workflow',
    steps: [
      'Refresh or scan so the portfolio assessment reflects the latest repo state.',
      'Use Portfolio Mission and Work Queue to see which repos are blocked, ready, or already running.',
      'Open Operations when you need repo-specific context before acting on a selected repo.',
      'Fix missing README, roadmap, or structure issues before dispatching work.',
      'Use Evaluate, Audit, Repair, and README tools to standardize the repo contract.',
      'Pick the highest-value pending roadmap item and preview the Copilot task packet.',
      'Dispatch work, monitor Execution Queue, then re-run audits and export a Collection Status Report.',
    ],
  },
  {
    title: 'Update repositories',
    steps: [
      'Select specific repos in the Repository Grid, or leave all unchecked to target the full list.',
      'Click Pull to bring local repos up to date.',
      'Click Fetch when you only want remote tracking data refreshed.',
      'Open the Operation Log if you need to see detailed progress.',
    ],
  },
  {
    title: 'Create a roadmap for a repo that has none',
    steps: [
      'Open Work Queue and find the repo marked No Roadmap.',
      'Click Evaluate.',
      'Click Run Evaluation.',
      'Review and edit the Suggested ROADMAP.md draft.',
      'Click Create ROADMAP.md.',
      'Run Roadmap Scan or refresh so the new roadmap appears in the app.',
    ],
  },
  {
    title: 'Improve an existing roadmap',
    steps: [
      'Open Work Queue.',
      'Use Audit to see maturity and findings.',
      'Use Repair when the roadmap needs a structured rewrite.',
      'Review the proposed changes before applying.',
      'Use Lint to check formatting issues.',
    ],
  },
  {
    title: 'Prepare a repo for dispatched work',
    steps: [
      'Run a documentation audit from Work Queue.',
      'Fix missing README or documentation issues first.',
      'Confirm the roadmap has pending work and strong enough maturity.',
      'Use Dispatch Release when the repo is ready.',
      'Check Execution Queue for active or recently dispatched work.',
    ],
  },
  {
    title: 'Create a report',
    steps: [
      'Select repos if you only want a subset of the portfolio.',
      'Click Report.',
      'Wait for the Operation Log to show the saved HTML and CSV paths.',
      'Use the opened Collection Status Report to review lifecycle states, blockers, next actions, and top recommended work.',
    ],
  },
];

const tips = [
  'Use Refresh when the screen feels stale after file changes outside the app.',
  'Use Roadmap Scan after adding or moving ROADMAP files.',
  'Use Work Queue when you want next actions, not just repository status.',
  "Use Operations when you need one repo's local path, GitHub state, dirty summary, and next recommended action in one place.",
  'Use Report after scans, repairs, or dispatch to capture lifecycle states, blockers, and the highest-value next work in one artifact.',
  'A ROADMAP button means a roadmap exists. Missing roadmap work starts from Evaluate.',
  'Preview screens are intentionally separate from apply buttons so you can review changes first.',
  'If a popup reports that a path cannot be resolved, check Settings and scan depth.',
];

function NumberedSteps({ steps }: { steps: string[] }) {
  return (
    <ol className="space-y-2">
      {steps.map((step, index) => (
        <li key={step} className="flex gap-3 text-sm text-gray-300">
          <span className="mt-0.5 inline-flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full bg-gray-800 text-xs text-blue-300 border border-gray-700">
            {index + 1}
          </span>
          <span>{step}</span>
        </li>
      ))}
    </ol>
  );
}

const HelpModal: React.FC<HelpModalProps> = ({ isOpen, onClose }) => {
  const [activeTab, setActiveTab] = useState<HelpTabId>('start');
  const active = useMemo(() => tabs.find(tab => tab.id === activeTab) ?? tabs[0], [activeTab]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/65 backdrop-blur-sm p-4">
      <div className="w-full max-w-5xl max-h-[92vh] overflow-hidden rounded-lg border border-gray-700 bg-gray-950 shadow-2xl">
        <div className="flex items-start justify-between gap-4 border-b border-gray-800 px-5 py-4">
          <div className="flex items-start gap-3">
            <div className="mt-0.5 flex h-9 w-9 items-center justify-center rounded-md border border-blue-700/50 bg-blue-950/50 text-blue-300">
              <HelpIcon className="h-5 w-5" />
            </div>
            <div>
              <div className="text-xs font-semibold uppercase tracking-wide text-blue-300">Help</div>
              <h2 className="text-lg font-semibold text-white">GitHub Repo Manager Guide</h2>
              <p className="mt-1 max-w-2xl text-sm text-gray-400">
                A simple walkthrough for using the main window, popups, and common repository workflows.
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-2xl leading-none text-gray-500 hover:text-gray-100"
            aria-label="Close help"
          >
            &times;
          </button>
        </div>

        <div className="grid min-h-0 grid-cols-1 md:grid-cols-[220px_1fr]">
          <nav className="border-b border-gray-800 bg-gray-900/50 p-3 md:border-b-0 md:border-r">
            <div className="space-y-1">
              {tabs.map(tab => (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`w-full rounded-md px-3 py-2 text-left text-sm transition-colors ${
                    activeTab === tab.id
                      ? 'bg-blue-900/40 text-blue-100 border border-blue-700/50'
                      : 'border border-transparent text-gray-400 hover:bg-gray-800 hover:text-gray-100'
                  }`}
                >
                  <span className="block text-xs text-gray-500">{tab.kicker}</span>
                  <span className="font-medium">{tab.label}</span>
                </button>
              ))}
            </div>
          </nav>

          <div className="max-h-[72vh] overflow-y-auto px-5 py-5">
            <div className="mb-5 border-b border-gray-800 pb-5">
              <div className="text-xs font-semibold uppercase tracking-wide text-blue-300">{active.kicker}</div>
              <h3 className="mt-1 text-xl font-semibold text-white">{active.title}</h3>
              <p className="mt-2 max-w-3xl text-sm leading-6 text-gray-300">{active.intro}</p>
            </div>

            {activeTab === 'start' && (
              <div className="space-y-6">
                <section>
                  <h4 className="text-sm font-semibold text-white">What this app is for</h4>
                  <p className="mt-2 text-sm leading-6 text-gray-300">
                    GitHub Repo Manager gives you one place to inspect many repositories, find which ones need work,
                    and move them toward a clean, documented, roadmap-driven state.
                  </p>
                </section>
                <section>
                  <h4 className="text-sm font-semibold text-white">What you can do here</h4>
                  <div className="mt-3 grid gap-3 sm:grid-cols-2">
                    {[
                      'Scan local repositories and classify their current state.',
                      'Pull or fetch updates across many repos.',
                      'Generate Collection Status Reports for the full portfolio or a selected slice.',
                      'Find missing README and roadmap work.',
                      'Create or improve ROADMAP.md files.',
                      'Prepare roadmap work for Copilot dispatch and progress reporting.',
                    ].map(item => (
                      <div key={item} className="rounded-md border border-gray-800 bg-gray-900/50 px-3 py-2 text-sm text-gray-300">
                        {item}
                      </div>
                    ))}
                  </div>
                </section>
                <section>
                  <h4 className="text-sm font-semibold text-white">Recommended first pass</h4>
                  <div className="mt-3">
                    <NumberedSteps
                      steps={[
                        'Confirm Backend is Online.',
                        'Confirm the workspace path is correct.',
                        'Review Portfolio Mission and Work Queue first.',
                        'Use Evaluate, Audit, Repair, or README tools to clear blockers.',
                        'Use Report after major changes to capture the latest collection snapshot.',
                      ]}
                    />
                  </div>
                </section>
                <section>
                  <h4 className="text-sm font-semibold text-white">North-star workflow</h4>
                  <div className="mt-3">
                    <NumberedSteps
                      steps={[
                        'Assess the full collection.',
                        'Fix README, roadmap, and structure blockers.',
                        'Rank the highest-value pending work.',
                        'Preview and refine the Copilot task packet.',
                        'Dispatch, monitor, validate, and report progress.',
                      ]}
                    />
                  </div>
                </section>
              </div>
            )}

            {activeTab === 'main-window' && (
              <div className="grid gap-3 sm:grid-cols-2">
                {mainWindowSections.map(section => (
                  <section key={section.title} className="rounded-md border border-gray-800 bg-gray-900/40 p-3">
                    <h4 className="text-sm font-semibold text-white">{section.title}</h4>
                    <p className="mt-1 text-sm leading-6 text-gray-400">{section.body}</p>
                  </section>
                ))}
              </div>
            )}

            {activeTab === 'popups' && (
              <div className="grid gap-3 sm:grid-cols-2">
                {popupSections.map(section => (
                  <section key={section.title} className="rounded-md border border-gray-800 bg-gray-900/40 p-3">
                    <h4 className="text-sm font-semibold text-white">{section.title}</h4>
                    <p className="mt-1 text-sm leading-6 text-gray-400">{section.body}</p>
                  </section>
                ))}
              </div>
            )}

            {activeTab === 'workflows' && (
              <div className="space-y-5">
                {workflows.map(workflow => (
                  <section key={workflow.title} className="border-b border-gray-800 pb-5 last:border-b-0 last:pb-0">
                    <h4 className="text-sm font-semibold text-white">{workflow.title}</h4>
                    <div className="mt-3">
                      <NumberedSteps steps={workflow.steps} />
                    </div>
                  </section>
                ))}
              </div>
            )}

            {activeTab === 'tips' && (
              <div className="space-y-3">
                {tips.map(tip => (
                  <div key={tip} className="flex gap-3 rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-sm text-gray-300">
                    <span className="mt-2 h-1.5 w-1.5 flex-shrink-0 rounded-full bg-blue-400" />
                    <span>{tip}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        <div className="flex justify-end border-t border-gray-800 px-5 py-3">
          <button
            onClick={onClose}
            className="rounded-md border border-gray-700 bg-gray-900 px-4 py-1.5 text-sm text-gray-200 hover:border-gray-500 hover:bg-gray-800"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
};

export default HelpModal;
