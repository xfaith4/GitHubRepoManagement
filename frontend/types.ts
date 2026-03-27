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

export type OperationType = 'init' | 'update' | 'sync' | 'export' | 'archive' | 'docreview' | 'scan' | 'roadmap-scan' | 'roadmap-agent' | 'docs-audit-scan' | 'copilot-task-preview' | 'roadmap-audit-scan' | 'roadmap-repair-preview' | 'roadmap-repair-apply' | 'roadmap-lint-scan' | 'readme-standardize-preview' | 'readme-standardize-apply' | 'roadmap-dispatch-check' | 'roadmap-dispatch-execute' | 'readme-generate' | 'readme-generate-apply';

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

// Release 0.8 — Roadmap Contract Audit & Maturity Scoring

export type RoadmapMaturityLevel =
  | 'L0-Absent'
  | 'L1-Informal'
  | 'L2-Structured'
  | 'L3-Contract-Ready'
  | 'L4-Orchestration-Ready';

export type RoadmapMaturityFilter = RoadmapMaturityLevel | 'all';

// Per-rule finding returned by the roadmap auditor
export interface RoadmapAuditFinding {
  ruleId: string;
  severity: 'critical' | 'warning' | 'info';
  message: string;
  recommendedAction?: string | null;
  scoreImpact?: number | null;
}

// Normalized roadmap contract with audit score — matches roadmap-contract.schema.json
export interface RoadmapAuditEntry {
  schemaVersion: string;
  repoName: string;
  repoPath?: string | null;
  roadmapPath?: string | null;
  roadmapState: 'pending' | 'complete' | 'missing' | 'parse-error';
  maturityLevel: RoadmapMaturityLevel;
  maturityScore: number;
  pendingCount: number;
  completedCount: number;
  totalCount: number;
  nextPendingItem?: { text: string; section: string; tags?: string[] } | null;
  sections: Array<{ name: string; pendingItems: string[]; completedItems: string[] }>;
  hasProductIntent?: boolean | null;
  hasReleaseSections?: boolean | null;
  hasAcceptanceCriteria?: boolean | null;
  hasOutOfScope?: boolean | null;
  releaseCount?: number | null;
  vagueItemCount?: number;
  parseError?: string | null;
  auditFindings?: RoadmapAuditFinding[] | null;
  parsedAt: string;
}

// Index returned by GET /api/roadmap/audit and POST /api/roadmap/audit/scan
export interface RoadmapAuditIndex {
  entries: RoadmapAuditEntry[];
  auditedAt: string;
  count: number;
  cacheSource: 'fresh-scan' | 'cache' | 'memory' | 'disk';
  cacheAgeSeconds: number;
}


// Release 0.9 — Roadmap Repair Preview & Standardization Workflow

export type RoadmapRepairPreviewState =
  | 'repair-preview-ready'
  | 'repair-blocked'
  | 'rewrite-not-recommended';

// A single concrete repair action produced by the planner
export interface RoadmapRepairAction {
  actionId: string;
  description: string;
  affectsSection: string;
  severity: 'critical' | 'warning' | 'info';
}

// Full repair preview returned by POST /api/roadmap/repair/preview
export interface RoadmapRepairPreview {
  previewId: string;
  previewState: RoadmapRepairPreviewState;
  blockReason?: string | null;
  repoName: string;
  roadmapPath?: string | null;
  originalMaturityLevel: RoadmapMaturityLevel;
  originalMaturityScore: number;
  currentContent: string;
  proposedContent?: string | null;
  repairActions: RoadmapRepairAction[];
  auditFindings?: RoadmapAuditFinding[] | null;
  completedItemCount: number;
  pendingItemCount: number;
  generatedAt: string;
}

// History record returned by GET /api/roadmap/repair/history
export interface RoadmapRepairHistoryItem {
  previewId: string;
  repoName: string;
  roadmapPath?: string | null;
  previewState: string;
  originalMaturityLevel: string;
  event: 'preview' | 'apply';
  timestamp: string;
  appliedAt?: string | null;
}

// Release 1.0 — Two-Lane Execution Queue

export type ExecutionState =
  | 'idle'
  | 'ready'
  | 'running'
  | 'blocked'
  | 'complete';

export interface ExecutionLaneEntry {
  repoName: string;
  repoPath?: string;
  executionState: ExecutionState;
  roadmapPath?: string;
  currentTaskText?: string;
  currentTaskSection?: string;
  currentRunId?: string | null;
  laneSlot?: number | null;
  priorityScore: number;
  assignedAt?: string | null;
  completedAt?: string | null;
  lastOutcome?: string | null;
  retryCount: number;
  errorMessage?: string | null;
  updatedAt: string;
}

export interface ExecutionLaneStateCounts {
  idle: number;
  ready: number;
  running: number;
  blocked: number;
  complete: number;
}

export interface ExecutionQueueSummary {
  schemaVersion: string;
  updatedAt: string;
  totalRepos: number;
  stateCounts: ExecutionLaneStateCounts;
  activeLaneCount: number;
  lanes: {
    lane1: ExecutionLaneEntry | null;
    lane2: ExecutionLaneEntry | null;
  };
  rankedQueue: ExecutionLaneEntry[];
  entries: ExecutionLaneEntry[];
  recentHistory: ExecutionHistoryRecord[];
}

export interface ExecutionHistoryRecord {
  repoName: string;
  event: 'assigned' | 'completed' | 'cancelled' | 'requeued';
  runId?: string;
  taskText?: string;
  outcome?: string;
  errorMessage?: string;
  timestamp: string;
}

// Release 1.1 — Standardization, Guardrails, and Continuous Improvement

// Roadmap Lint Finding
export interface RoadmapLintFinding {
  ruleId: string;
  severity: 'error' | 'warning' | 'info';
  message: string;
  line?: number | null;
  recommendedAction?: string | null;
}

// Roadmap Lint Result (per repo)
export interface RoadmapLintResult {
  repoName: string;
  lintPassed: boolean;
  findings: RoadmapLintFinding[];
  summary: string;
  lintedAt: string;
}

// README Standardization Preview
export type ReadmeStandardizationPreviewState =
  | 'standardization-preview-ready'
  | 'standardization-blocked'
  | 'already-standard';

export interface ReadmeStandardizationAction {
  actionId: string;
  description: string;
  severity: 'error' | 'warning' | 'info';
}

export interface ReadmeStandardizationPreview {
  previewId: string;
  repoName: string;
  previewState: ReadmeStandardizationPreviewState;
  blockReason?: string | null;
  currentContent: string;
  proposedContent?: string | null;
  standardizationActions: ReadmeStandardizationAction[];
  generatedAt: string;
}

export interface ReadmeStandardizationHistoryItem {
  previewId: string;
  repoName: string;
  repoPath?: string | null;
  event: 'preview' | 'apply';
  timestamp: string;
  appliedAt?: string | null;
}

// Release 1.5 — Copilot-Assisted README Generation

export interface ReadmeGenerationResult {
  generationId: string;
  repoName: string;
  localPath: string;
  repoType: string;
  contextSummary: string;
  previewContent: string;
  generatedAt: string;
}

export interface ReadmeGenerationApplyResult {
  repoName: string;
  readmePath: string;
  writtenAt: string;
}

export interface ReadmeGenerationHistoryItem {
  generationId: string;
  repoName: string;
  localPath?: string | null;
  repoType?: string | null;
  contextSummary?: string | null;
  generatedAt: string;
  appliedAt?: string | null;
  readmePath?: string | null;
}

// Maturity Drift Alert
export type DriftSeverity = 'critical' | 'warning';

export interface MaturityDriftAlert {
  repoName: string;
  targetLevel: string;
  currentLevel: string;
  currentScore: number;
  driftSeverity: DriftSeverity;
  detectedAt: string;
  lastAcknowledgedAt?: string | null;
}

export interface MaturityDriftResult {
  driftAlerts: MaturityDriftAlert[];
  baselineCount: number;
  driftCount: number;
  evaluatedAt: string;
}

// Notification Webhooks
export interface NotificationWebhook {
  id: string;
  url: string;
  label: string;
  events: string[];
  registeredAt: string;
  enabled: boolean;
  lastFiredAt?: string | null;
  lastFireResult?: string | null;
}

// Roadmap Completion Preview
export interface RoadmapCompletionPreview {
  previewId: string;
  repoName: string;
  roadmapPath?: string | null;
  currentContent: string;
  proposedContent: string;
  markedCount: number;
  completedItems: string[];
  generatedAt: string;
}

// Release 1.2 — Execution metrics, auto-scan schedule, cross-repo dependency graph

export interface ExecutionMetrics {
  completedToday: number;
  completedThisWeek: number;
  totalCompleted: number;
  totalCancelled: number;
  avgCurrentRunMins: number;
  errorRatePct: number;
  stateCounts: {
    idle: number;
    ready: number;
    running: number;
    blocked: number;
    complete: number;
  };
}

export interface ScanSchedule {
  enabled: boolean;
  intervalMinutes: number;
  nextScanAt: string | null;
  lastScanAt: string | null;
}

export interface RoadmapDependencyRef {
  targetRepo: string;
  context: string;
  lineNumber: number;
  pattern: 'github-url' | 'hash-ref' | 'keyword';
}

export interface RoadmapDependencySummaryEntry {
  repoName: string;
  dependsOn: string[];
  dependedOnBy: string[];
}

export interface RoadmapDependencyGraph {
  graph: Record<string, RoadmapDependencyRef[]>;
  summary: RoadmapDependencySummaryEntry[];
  totalEdges: number;
  scannedAt: string;
}

// Release 1.4 — Repo Evaluation Pipeline

export type EvaluationFindingSeverity = 'critical' | 'high' | 'medium' | 'low';
export type EvaluationFindingCategory = 'hardening' | 'documentation' | 'ci' | 'testing' | 'security' | 'compliance';
export type RepoType = 'node' | 'dotnet' | 'python' | 'rust' | 'powershell' | 'other';

export interface EvaluationFinding {
  findingId: string;
  category: EvaluationFindingCategory;
  severity: EvaluationFindingSeverity;
  title: string;
  description: string;
  roadmapItem: string;
}

export interface EvaluationSuggestedAddition {
  severity: EvaluationFindingSeverity;
  category: EvaluationFindingCategory;
  title: string;
  roadmapItem: string;
}

export interface RepoEvaluationResult {
  evaluationId: string;
  repoName: string;
  localPath: string;
  repoType: RepoType;
  evaluatedAt: string;
  hasExistingRoadmap: boolean;
  findings: EvaluationFinding[];
  findingCount: number;
  criticalCount: number;
  highCount: number;
  suggestedRoadmapContent: string | null;
  suggestedAdditions: EvaluationSuggestedAddition[];
}

// Release 1.6 — Roadmap-Driven Release Dispatch to GitHub Copilot

export interface PendingRelease {
  releaseName: string;
  releaseVersion: string;
  releaseTitle: string;
  goal: string;
  pendingMilestones: string[];
  completedMilestones: string[];
  acceptanceCriteria: string[];
  outOfScope: string[];
  milestoneCount: number;
  pendingCount: number;
  completedCount: number;
}

export interface ReleaseDispatchPacket {
  packetVersion: string;
  packetId: string;
  createdAt: string;
  repoName: string;
  githubRepo: string;
  roadmapPath: string;
  releaseName: string;
  releaseVersion: string;
  releaseGoal: string;
  pendingMilestones: string[];
  acceptanceCriteria: string[];
  outOfScope: string[];
  generatedPrompt: string;
  maturityLevel: RoadmapMaturityLevel;
  maturityScore: number;
}

export interface ReleaseDispatchCheck {
  repoName: string;
  maturityLevel: RoadmapMaturityLevel;
  maturityScore: number;
  dispatchReady: boolean;
  localPath?: string | null;
  roadmapPath?: string | null;
  repairPreview?: RoadmapRepairPreview | null;
  releasePacket?: ReleaseDispatchPacket | null;
}

export interface DispatchExecuteResult {
  runId: string;
  status: 'started' | 'failed';
  githubRepo: string;
  startedAt: string;
  message: string;
  error?: string | null;
}

// Release 1.7 — Repo Git Status Detail: Dirty badge visibility and action pathways

export interface GitStatusFile {
  status: string;       // single-char git status code: M, A, D, R, C, ?
  path: string;
  origPath?: string | null;  // for renames: the old path
}

export interface GitCommitRef {
  hash: string;
  message: string;
}

export interface RepoGitStatusDetail {
  repoName: string;
  localPath: string;
  branch: string;
  upstream: string;
  isMidMerge?: boolean;
  isMidRebase?: boolean;
  stagedFiles: GitStatusFile[];
  unstagedFiles: GitStatusFile[];
  untrackedFiles: GitStatusFile[];
  conflictedFiles: GitStatusFile[];
  stagedCount: number;
  unstagedCount: number;
  untrackedCount: number;
  conflictedCount: number;
  unpushedCommits: GitCommitRef[];
  unpulledCommits: GitCommitRef[];
  unpushedCount: number;
  unpulledCount: number;
  stashCount: number;
  scannedAt: string;
}

export interface GitActionResult {
  success: boolean;
  output: string;
  error?: string | null;
}
