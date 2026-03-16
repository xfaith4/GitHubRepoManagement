// Fix: Replaced mock data and implementation with proper type exports to resolve circular dependencies and export errors.

export interface RepoStatus {
  name: string;
  status: 'clean' | 'dirty' | 'ahead' | 'behind' | 'diverged';
  branch: string;
  lastCommitDate: string;
  lastCommitMessage: string;
  lastCommitAuthor: string;
  localAhead: number;
  remoteAhead: number;
  uncommittedChanges: number;
  isArchived: boolean;
  isStale: boolean;
  hasArtifacts?: boolean;
  lastBuildStatus?: 'success' | 'failure' | 'in_progress' | 'none';
  lastBuildUrl?: string;
  openPrCount?: number;
  commitsLastWeek?: number;
  commitsLastMonth?: number;
  activeContributorsLastWeek?: number;
  activeContributorsLastMonth?: number;
  artifactCount?: number;
  repoSizeKb?: number;
  pendingReviewPrCount?: number;
  actionsWorkflowCount?: number;
  testingWorkflowCount?: number;
  actionsEnabled?: boolean;
  htmlUrl?: string;
  localPath?: string;
  originUrl?: string;
  owner?: string;
  visibility?: string;
  language?: string | null;
  topics?: string[];

  hasRoadmap?: boolean;
  roadmapState?: 'missing' | 'complete' | 'pending' | 'parse-error';
  nextPendingRoadmapItem?: string;
  dispatchReadiness?: DispatchReadiness;

  // Optional extended metrics
  extended?: ExtendedRepoMetrics;
  branches?: BranchInfo[];
  issueStats?: IssueStats;
}

export interface AppSettings {
  basePath: string;
  reportPath: string;
  staleThreshold: number;
  daysInactive: number;
  zipArchive: boolean;
  scanDepth: number;
  githubUser?: string;
  githubToken?: string;
}

export interface Artifact {
  name: string;
  size: number;
  createdAt: string;
  downloadUrl: string;
}

export interface OperationRepoResult {
  name: string;
  path?: string;
  success: boolean;
  output?: string;
  error?: string;
}

export interface OperationResult {
  operation: 'pull' | 'sync';
  total: number;
  succeeded: number;
  failed: number;
  results: OperationRepoResult[];
}

export interface ReportExportResult {
  generatedAt: string;
  repoCount: number;
  sourceLabel: string;
  reportFileName: string;
  reportPath: string;
  reportUrl: string;
  csvFileName: string;
  csvPath: string;
}

export type OperationType = 'init' | 'update' | 'sync' | 'export' | 'archive' | 'docreview' | 'scan' | 'roadmap-scan' | 'roadmap-agent' | 'docs-audit-scan' | 'copilot-task-preview';

export interface GithubInsightsMeta {
  totalRepos: number;
  fetchedRepos: number;
  rateLimit?: {
    remaining: number;
    limit: number;
    reset: number;
  } | null;
}

export interface DocReviewRunRequest {
  rootPath?: string;
  maxDepth?: number;
  outDir?: string;
  targetRepo?: string;
  generateQueue?: boolean;
  generateBatchPlan?: boolean;
}

export interface DocReviewRunResult {
  inventoryManifestPath: string;
  inventorySummaryCsvPath: string;
  inventoryReportPath: string;
  queuePath?: string | null;
  workitemsRoot?: string | null;
}

// Extended metrics for repository insights
export interface ExtendedRepoMetrics {
  // Issues
  openIssuesCount: number;
  closedIssuesCount: number;
  issuesClosedLast30Days: number;
  oldestOpenIssueDays: number | null;

  // Branches
  totalBranches: number;
  staleBranches: number;
  protectedBranches: number;
  defaultBranchProtected: boolean;

  // Projects
  projectsCount: number;
  activeProjects: number;

  // Releases
  latestRelease: string | null;
  latestReleaseDate: string | null;
  totalReleases: number;

  // Health & Security
  healthScore: number;
  hasReadme: boolean;
  hasLicense: boolean;
  hasSecurityPolicy: boolean;
  vulnerabilitiesCount: number;

  // Social
  stars: number;
  forks: number;
  watchers: number;
}

// Branch information
export interface BranchInfo {
  name: string;
  isProtected: boolean;
  isStale: boolean;
  lastCommitDate: string;
  daysSinceUpdate: number;
  isDefault: boolean;
}

// Issue statistics
export interface IssueStats {
  open: number;
  closed: number;
  openBugs: number;
  openEnhancements: number;
  avgResolutionDays: number | null;
  oldestOpenDays: number | null;
}

export interface RoadmapEntry {
  repoName: string;
  repoPath: string;
  roadmapPath: string;
  lastModified: string;
  sizeBytes: number;
  roadmapState?: 'complete' | 'pending' | 'parse-error';
  pendingCount?: number;
  completedCount?: number;
  nextPendingItem?: { text: string; section: string } | null;
}

export interface RoadmapIndex {
  entries: RoadmapEntry[];
  scannedAt: string;
  count: number;
  cacheSource: 'fresh-scan' | 'cache' | 'memory' | 'disk';
  cacheAgeSeconds: number;
}

export interface RoadmapContent {
  repoName: string;
  content: string;
  path: string;
  sizeBytes: number;
  lastModified: string;
}

export interface RoadmapTaskCandidate {
  heading: string;
  lineNumber: number;
  text: string;
}

export interface RoadmapTaskHistoryInfo {
  rootPath: string;
  runEventsPath: string;
  runSummaryPath: string;
  historyPath: string;
}

export interface RoadmapTaskPreview {
  runId: string;
  repository: string;
  roadmapPath: string;
  selectedTask: RoadmapTaskCandidate;
  followUpCandidates: RoadmapTaskCandidate[];
  generatedTaskDescription: string;
  history: RoadmapTaskHistoryInfo;
}

export interface RoadmapTaskHistoryItem {
  runId: string;
  status: string;
  repository: string;
  selectedTask: string;
  roadmapPath: string;
  startedAt: string;
  completedAt: string;
  error?: string;
  summaryPath: string;
}

// Dispatch readiness states for Release 0.5
export type DispatchReadiness =
  | 'ready'
  | 'needs-doc-standardization'
  | 'missing-roadmap'
  | 'roadmap-complete'
  | 'parse-error'
  | 'blocked';

// A single documentation finding for a repository
export interface DocFinding {
  file: string;
  message: string;
  severity: 'critical' | 'warning' | 'info';
  recommendedAction: string;
}

// Per-repo documentation audit result
export interface DocAuditEntry {
  repoName: string;
  repoPath: string;
  dispatchReadiness: DispatchReadiness;
  docFindings: DocFinding[];
  roadmapState?: 'missing' | 'complete' | 'pending' | 'parse-error';
  nextPendingRoadmapItem?: string | null;
  auditedAt: string;
  criticalCount: number;
  warningCount: number;
  infoCount: number;
  readyForDispatch: boolean;
}

// Docs audit index returned by /api/docs-audit
export interface DocAuditIndex {
  entries: DocAuditEntry[];
  auditedAt: string;
  count: number;
  cacheSource: 'fresh-scan' | 'cache' | 'memory' | 'disk';
  cacheAgeSeconds: number;
}

// Release 0.6 — Copilot Task Packaging & Preview Workflow

export interface CopilotTaskPacketContext {
  repoName: string;
  repoPath?: string;
  roadmapPath: string;
  dispatchReadiness?: DispatchReadiness;
}

export interface CopilotTaskPacketRoadmapItem {
  text: string;
  section: string;
  previousItem?: string | null;
  nextItem?: string | null;
}

export interface CopilotTaskPacketGuardrail {
  rule: string;
}

export interface CopilotTaskPacket {
  packetVersion: string;
  runId: string;
  createdAt: string;
  repoContext: CopilotTaskPacketContext;
  selectedRoadmapItem: CopilotTaskPacketRoadmapItem;
  followUpCandidates: Array<{ text: string; section: string }>;
  docFindings: DocFinding[];
  acceptanceCriteria: string[];
  guardrails: CopilotTaskPacketGuardrail[];
  generatedPrompt: string;
  historyPath?: string;
  runEventsPath?: string;
  runSummaryPath?: string;
}

export interface CopilotTaskHistoryItem {
  runId: string;
  status: string;
  repoName: string;
  roadmapItem: string;
  roadmapPath: string;
  startedAt: string;
  completedAt?: string;
  error?: string;
  summaryPath?: string;
}
