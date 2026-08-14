// Fix: Replaced mock data and implementation with proper type exports to resolve circular dependencies and export errors.

/**
 * Release 3.1 — how far this clone has drifted from its remote, and what that
 * answer is based on.
 *
 * `isStale` alone was a hardcoded `false` in every scan path for several
 * releases while the dashboard rendered a Stale column from it, so this type
 * carries the basis and the magnitude rather than a bare boolean: a reader can
 * tell "measured and current" from "never looked".
 *
 * `exactCountsAvailable` is false for the timestamp basis. Two dates cannot
 * produce a commit count — that needs a ref comparison — so `localAhead` and
 * `remoteAhead` stay unwritten rather than being filled with a plausible zero.
 */
export interface RepoStaleness {
  state: 'behind' | 'ahead-or-unpushed' | 'current' | 'unknown';
  isStale: boolean;
  basis: string;
  localCommitDate: string | null;
  remotePushedAt: string | null;
  driftSeconds: number | null;
  behindByDays: number | null;
  toleranceSeconds: number;
  exactCountsAvailable: boolean;
  summary: string;
}

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
  staleness?: RepoStaleness | null;
  /** GitHub `pushed_at` — when the remote default branch last received commits. */
  remotePushedAt?: string | null;
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
  hasPages?: boolean;
  pagesUrl?: string;
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
  changeState?: PortfolioChangeState;
  scanDecisionReason?: PortfolioScanDecisionReason;
  headCommitSha?: string | null;
  lastIndexedCommitSha?: string | null;
  lastScanStatus?: PortfolioScanStatus;
  lastScanError?: string | null;
  repoId?: string;
  curationState?: RepoCurationState;
  curationUpdatedAt?: string | null;

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
  /**
   * NAME of the environment variable holding the GitHub token — never the
   * token itself. The host reads the variable at runtime; no secret is stored
   * in settings.json or transmitted from the browser.
   */
  gitHubTokenEnvVar?: string;
}

/** Reported by GET /api/auth/github/status — diagnostics for the env var name. */
export interface GitHubAuthStatus {
  mode: 'pat' | 'gh-cli' | 'github-app' | 'none';
  tokenEnvVar: string;
  tokenSource: 'env' | 'gh-cli' | 'none';
  tokenEnvScope: string;
  runningAsService: boolean;
  hint: string;
  ghCliPresent: boolean;
  liveCheck?: {
    checked: boolean;
    valid: boolean;
    login?: string;
    expiresAt?: string;
    error?: string;
  } | null;
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
  activeRelease?: RoadmapReleaseSummary | null;
  activePhasePlan?: RoadmapPhasePlan | null;
  budgetGuardrail?: RoadmapBudgetGuardrail | null;
  estimatedSessionWorkUnits?: number | null;
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

export interface ReadmeContent {
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

export interface RepositoryImprovementFinding {
  source: 'readme' | 'roadmap';
  file: 'README.md' | 'ROADMAP.md';
  ruleId?: string | null;
  severity: 'critical' | 'warning' | 'info';
  message: string;
  recommendedAction: string;
}

export interface RepositoryImprovementDocumentResult {
  exists: boolean;
  path?: string | null;
  findingCount: number;
  findings: RepositoryImprovementFinding[];
}

export interface RepositoryImprovementTask {
  taskId: string;
  title: string;
  summary: string;
  acceptanceCriteria: string[];
  generatedPrompt: string;
}

export interface RepositoryImprovementPreview {
  repoName: string;
  repoPath: string;
  scannedAt: string;
  needsImprovement: boolean;
  findingCount: number;
  findings: RepositoryImprovementFinding[];
  readme: RepositoryImprovementDocumentResult;
  roadmap: RepositoryImprovementDocumentResult & {
    state: 'pending' | 'complete' | 'missing' | 'parse-error';
    maturityLevel: RoadmapMaturityLevel;
    maturityScore: number;
    pendingCount: number;
  };
  task?: RepositoryImprovementTask | null;
  engine?: EngineAttribution | null;
}

/**
 * Release 3.1 — which engine produced what the operator is looking at.
 *
 * A deterministic rule's finding and a model's proposal carry very different
 * weight, and a surface that renders them identically asks the operator to
 * trust both the same amount. `providerId` and `modelId` are null for rule
 * engines and populated for model ones, so a consumer can branch on the data
 * rather than on the surface it happens to be rendering.
 */
export interface EngineAttribution {
  kind: 'deterministic-rules' | 'model';
  label: string;
  detail: string;
  providerId?: string | null;
  modelId?: string | null;
  ruleSources?: string[];
  appliesTo?: string[];
  /** The engine that acts *after* this one, when the surface hands off. */
  handoffEngine?: string | null;
}

// Release 0.6 — Copilot Task Packaging & Preview Workflow

export interface CopilotTaskPacketContext {
  repoName: string;
  repoPath?: string;
  roadmapPath: string;
  dispatchReadiness?: DispatchReadiness;
  lifecycleState?: RepoLifecycleState | null;
  recommendedAction?: string | null;
  blockingReasons?: string[];
  maturityLevel?: RoadmapMaturityLevel | null;
  maturityScore?: number | null;
  sourceCoverage?: SourceCoverage | null;
  dispatchReadinessExplanation?: string | null;
  readmeScore?: number | null;
  roadmapScore?: number | null;
  documentationHealthScore?: number | null;
  pendingItemCount?: number | null;
}

export interface CopilotTaskPacketReadmeContext {
  readmePath?: string | null;
  summary: string;
  headings: string[];
  hasSetupGuidance: boolean;
  hasUsageGuidance: boolean;
  hasArchitectureGuidance: boolean;
}

export interface CopilotTaskPacketRoadmapContext {
  releaseName?: string | null;
  releaseVersion?: string | null;
  releaseTitle?: string | null;
  releaseGoal: string;
  pendingMilestones: string[];
  completedMilestones: string[];
  acceptanceCriteria: string[];
  outOfScope: string[];
}

export interface CopilotTaskPacketRoadmapItem {
  text: string;
  section: string;
  tags?: string[];
  previousItem?: string | null;
  nextItem?: string | null;
  selectionSource?: 'value-ranked' | 'roadmap-order';
}

export interface CopilotTaskPacketGuardrail {
  rule: string;
}

export interface CopilotTaskPacketValueContext {
  selectedBy: 'value-ranked' | 'roadmap-order' | 'operator-selected';
  selectedIsTopValueItem: boolean;
  topValueItemText?: string | null;
  valueScore?: number | null;
  valueTier?: PortfolioValueTier | null;
  rationale: string[];
}

export interface CopilotTaskPacketConstraint {
  source: string;
  text: string;
}

export interface CopilotTaskPacket {
  packetVersion: string;
  runId: string;
  createdAt: string;
  repoContext: CopilotTaskPacketContext;
  readmeContext: CopilotTaskPacketReadmeContext;
  roadmapContext: CopilotTaskPacketRoadmapContext;
  selectedRoadmapItem: CopilotTaskPacketRoadmapItem;
  followUpCandidates: Array<{ text: string; section: string }>;
  docFindings: DocFinding[];
  valueContext: CopilotTaskPacketValueContext;
  constraints: CopilotTaskPacketConstraint[];
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
export type EvaluationFindingCategory =
  | 'hardening'
  | 'documentation'
  | 'ci'
  | 'testing'
  | 'security'
  | 'compliance'
  | 'modernization'
  | 'feature'
  | 'user-value';
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

export interface RoadmapReleaseSummary {
  releaseName?: string | null;
  releaseVersion?: string | null;
  releaseTitle?: string | null;
}

export interface RoadmapPhasePlan {
  phaseName: string;
  scope?: string | null;
  status?: string | null;
  completed?: string | null;
  tokenUsage?: string | null;
  workUnitsEstimated?: number | null;
  workUnitsActual?: number | null;
}

export interface RoadmapBudgetGuardrail {
  estimatedReleaseWorkUnits?: number | null;
  maxUnitsPerPhase?: number | null;
  notes?: string[];
}

export interface DispatchQuotaSummary {
  estimatedWorkUnits: number;
  estimateSource?: string | null;
  warning?: string | null;
  projectBudgetUnitsRemaining?: number | null;
  plannedReleaseName?: string | null;
  plannedPhaseName?: string | null;
}

export interface DispatchExecuteResult {
  runId: string;
  agentRunId?: string | null;
  /**
   * Release 3.0: `queued`, not `started`. The API host enqueues for the
   * operator-session runner — it cannot start a cloud agent task itself,
   * because `gh agent-task` needs an OAuth credential a LocalSystem service
   * structurally cannot hold. `started` remains for older recorded results.
   */
  status: 'queued' | 'started' | 'failed';
  dispatchTarget?: 'claude' | 'copilot';
  githubRepo: string;
  branch?: string | null;
  startedAt: string;
  message: string;
  /** Whether a runner is present to pick the queued work up. */
  runner?: import('./lib/runnerPresence').RunnerPresencePayload | null;
  /**
   * Release 3.1 — true only when the operator overrode the presence gate with
   * `acknowledgeNoRunner`. Without that flag the route refuses (409
   * `runner-absent`) and writes nothing, so this can never be a surprise.
   */
  queuedWithoutRunner?: boolean;
  /** Queued work nothing can claim, counting the task just queued. */
  strandedCount?: number;
  quota?: DispatchQuotaSummary | null;
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

// Release 1.7.5 — Portfolio Mission Alignment

export type RepoLifecycleState =
  | 'discovered'
  | 'needs-readme'
  | 'needs-roadmap'
  | 'needs-roadmap-repair'
  | 'needs-structure'
  | 'ready-for-work'
  | 'running'
  | 'completed'
  | 'monitored'
  | 'archived'
  | 'parse-error';

export type SourceCoverage = 'local' | 'github' | 'local+github';

export interface RepoStructureFinding {
  kind: 'missing-root-file' | 'missing-root-folder' | 'missing-ci-signal' | 'missing-test-signal';
  target: string;
  category: string;
  severity: 'critical' | 'warning' | 'info';
  recommendedAction: string;
}

export type PortfolioValueTier = 'highest' | 'high' | 'medium' | 'low' | 'deferred' | 'unscored';

export interface PortfolioPendingItemValue {
  text: string;
  section: string;
  tags: string[];
  roadmapOrder: number;
  valueScore: number;
  valueTier: PortfolioValueTier;
  valueRationale: string[];
  scoringSignals: {
    dimensions?: Record<string, number>;
    weights?: Record<string, number>;
    modelVersion?: string;
  };
}

export type PortfolioChangeState = 'unchanged' | 'new-commits' | 'metadata-changed' | 'needs-rescan' | 'scan-failed';
export type PortfolioScanDecisionReason = 'reused-cache' | 'new-commit' | 'metadata-changed' | 'cache-miss' | 'cache-invalid' | 'forced-refresh';
export type PortfolioScanStatus = 'ok' | 'failed' | 'stale';
export type RepoCurationState = 'none' | 'favorite' | 'portfolio-candidate' | 'archived-ignore';

export interface PortfolioAssessmentEntry {
  repoName: string;
  localPath: string;
  htmlUrl: string;
  branch: string;
  gitStatus: string;
  isArchived: boolean;
  sourceCoverage: SourceCoverage;
  hasPages?: boolean;
  pagesUrl?: string | null;
  openPrCount?: number;
  pendingReviewPrCount?: number;
  latestWorkflowRunStatus?: string | null;
  latestWorkflowRunConclusion?: string | null;
  latestWorkflowRunName?: string | null;
  latestWorkflowRunTimestamp?: string | null;
  repoType: string;
  lifecycleState: RepoLifecycleState;
  recommendedAction: string;
  blockingReasons: string[];
  roadmapState: 'pending' | 'complete' | 'missing' | 'parse-error';
  roadmapPath: string;
  hasRoadmap: boolean;
  readmeScore?: number;
  roadmapScore?: number;
  documentationHealthScore?: number;
  pendingItemCount: number;
  nextPendingItemText: string;
  pendingItems: PortfolioPendingItemValue[];
  topValueItem: PortfolioPendingItemValue | null;
  maturityLevel: RoadmapMaturityLevel;
  maturityScore: number;
  dispatchReadiness: DispatchReadiness;
  dispatchReadinessExplanation?: string;
  executionState: ExecutionState;
  hasReadme: boolean;
  hasCiSignal: boolean;
  hasTestSignal: boolean;
  structureFindings: RepoStructureFinding[];
  docFindingCount: number;
  activeRelease?: RoadmapReleaseSummary | null;
  activePhasePlan?: RoadmapPhasePlan | null;
  budgetGuardrail?: RoadmapBudgetGuardrail | null;
  estimatedSessionWorkUnits?: number | null;
  changeState?: PortfolioChangeState;
  scanDecisionReason?: PortfolioScanDecisionReason;
  headCommitSha?: string | null;
  headCommitDate?: string | null;
  headBranch?: string | null;
  currentMetadataHash?: string | null;
  lastIndexedCommitSha?: string | null;
  lastIndexedCommitDate?: string | null;
  lastIndexedBranch?: string | null;
  lastMetadataHash?: string | null;
  lastScannedAt?: string | null;
  lastScanStatus?: PortfolioScanStatus;
  lastScanError?: string | null;
  repoId?: string;
  curationState?: RepoCurationState;
  curationUpdatedAt?: string | null;
}

export interface PortfolioAssessmentSummary {
  totalRepos: number;
  byLifecycle: Record<RepoLifecycleState, number>;
  bySourceCoverage: Record<SourceCoverage, number>;
  missingReadmeCount: number;
  missingRoadmapCount: number;
  weakRoadmapCount: number;
  readyForWorkCount: number;
  runningCount: number;
  blockedCount: number;
}

export type PortfolioSignalSource = 'cache' | 'fresh-scan' | 'ledger' | 'api' | 'unavailable' | 'not-evaluated' | 'no-token' | 'no-owner-configured' | 'error';

export interface PortfolioAssessmentScanSummary {
  reused: number;
  reindexed: number;
  failed: number;
  durationMs: number;
}

// Release 3.2 — portfolio read-path performance budget. The measured duration
// travels WITH the budget it was judged against, so a consumer never has to go
// and look up the target to know whether the number is good. `declared: false`
// means the read class carries no budget at all; it fails closed to
// `withinBudget: false`, because an unbudgeted path is unmeasured, not fast.
export type PortfolioReadClass = 'memory' | 'portfolio-index' | 'assessment-cache' | 'fresh-scan';

export interface PortfolioReadBudget {
  readClass: PortfolioReadClass | string;
  declared: boolean;
  budgetMs: number;
  measuredMs: number;
  withinBudget: boolean;
  overByMs: number;
}

export interface PortfolioAssessmentResult {
  entries: PortfolioAssessmentEntry[];
  summary: PortfolioAssessmentSummary;
  signalSources: Partial<Record<'status' | 'roadmap' | 'docAudit' | 'roadmapAudit' | 'execution' | 'github', PortfolioSignalSource>>;
  generatedAt: string;
  count: number;
  cacheSource: 'memory' | 'fresh-scan';
  cacheAgeSeconds: number;
  scanSummary?: PortfolioAssessmentScanSummary;
  performance?: PortfolioReadBudget;
}

// Release 2.3 — Portfolio Analytics, Trend Visualization, and Distribution

export type PortfolioTrendStatus = 'history-backed' | 'current-snapshot-only';
export type PortfolioTrendSeedSource = 'portfolio-index' | 'assessment-cache';

export interface PortfolioTrendPoint {
  date: string;
  value: number;
}

export interface PortfolioTrendSeries {
  key: 'avgMaturityScore' | 'readyRepos';
  label: string;
  color: string;
  points: PortfolioTrendPoint[];
}

export interface PortfolioTrendSummary {
  totalRepos: number;
  readyForWorkCount: number;
  runningCount: number;
  blockedCount: number;
  completedCount: number;
  averageMaturityScore: number;
  averageDocumentationHealthScore: number;
  improvedThisWeek: number;
}

export interface PortfolioTrendTopCandidate {
  repoName: string;
  lifecycleState: RepoLifecycleState;
  maturityLevel: RoadmapMaturityLevel;
  maturityScore: number;
  documentationHealthScore: number;
  pendingItemCount: number;
  topValueItemText: string;
  valueScore: number;
  recommendedAction: string;
}

export interface PortfolioTrendRepoSparkline {
  repoName: string;
  lifecycleState: RepoLifecycleState;
  maturityLevel: RoadmapMaturityLevel;
  currentScore: number;
  points: PortfolioTrendPoint[];
  topValueItemText: string;
  recommendedAction: string;
}

export interface PortfolioTrendResult {
  trendStatus: PortfolioTrendStatus;
  seedSource: PortfolioTrendSeedSource;
  requestedDays: number;
  availableDays: number;
  generatedAt: string;
  note?: string | null;
  summary: PortfolioTrendSummary;
  series: PortfolioTrendSeries[];
  topCandidates: PortfolioTrendTopCandidate[];
  repoSparklines: PortfolioTrendRepoSparkline[];
}

// Release 1.8 — Operations Workspace and Prompt Refinement

export interface OperationsRepoEntry {
  repoId: string;
  ordinal: number;
  repoName: string;
  sourceCoverage: SourceCoverage;
  localPath: string;
  remoteUrl: string;
  githubOwner: string;
  githubRepo: string;
  githubFullName: string;
  htmlUrl: string;
  defaultBranch: string;
  currentBranch: string;
  hasPages: boolean;
  pagesUrl?: string | null;
  createdAt?: string | null;
  updatedAt?: string | null;
  latestWorkflowRunStatus?: string | null;
  latestWorkflowRunConclusion?: string | null;
  latestWorkflowRunName?: string | null;
  latestWorkflowRunTimestamp?: string | null;
  openPrCount: number;
  pendingReviewPrCount: number;
  localLastCommitDate?: string | null;
  localCommitsLastWeek: number;
  localCommitsLastMonth: number;
  localModifiedCount: number;
  localUntrackedCount: number;
  localDirtyCount: number;
  readmeLastWriteUtc?: string | null;
  roadmapLastWriteUtc?: string | null;
  repoType: string;
  lifecycleState: RepoLifecycleState;
  recommendedAction: string;
  blockingReasons: string[];
  roadmapState: 'pending' | 'complete' | 'missing' | 'parse-error';
  roadmapPath: string;
  hasRoadmap: boolean;
  hasReadme: boolean;
  readmeScore: number;
  roadmapScore: number;
  documentationHealthScore: number;
  pendingItemCount: number;
  nextPendingItemText: string;
  topValueItem: PortfolioPendingItemValue | null;
  maturityLevel: RoadmapMaturityLevel;
  maturityScore: number;
  dispatchReadiness: DispatchReadiness;
  dispatchReadinessExplanation?: string | null;
  executionState: ExecutionState;
  gitStatus: string;
  hasCiSignal: boolean;
  hasTestSignal: boolean;
  docFindingCount: number;
  structureFindings: RepoStructureFinding[];
  curationState: RepoCurationState;
  curationUpdatedAt?: string | null;
  changeState?: PortfolioChangeState;
  scanDecisionReason?: PortfolioScanDecisionReason;
  headCommitSha?: string | null;
  lastIndexedCommitSha?: string | null;
  lastScanStatus?: PortfolioScanStatus;
  lastScanError?: string | null;
}

export interface OperationsReposResult {
  entries: OperationsRepoEntry[];
  generatedAt: string;
  count: number;
  cacheSource: 'portfolio-index' | 'assessment-cache';
  summary: PortfolioAssessmentSummary | null;
}

export interface OperationsRepoDetail {
  repoId: string;
  repo: OperationsRepoEntry;
  documentationContext: {
    hasReadme: boolean;
    readmeLastWriteUtc?: string | null;
    hasRoadmap: boolean;
    roadmapPath?: string | null;
    roadmapLastWriteUtc?: string | null;
    docFindingCount: number;
    structureFindings: RepoStructureFinding[];
  };
  docAudit: {
    auditedAt?: string | null;
    dispatchReadiness: DispatchReadiness;
    criticalCount: number;
    warningCount: number;
    infoCount: number;
    findings: DocFinding[];
  };
  roadmapAudit: {
    auditedAt?: string | null;
    roadmapState: 'pending' | 'complete' | 'missing' | 'parse-error';
    maturityLevel: RoadmapMaturityLevel;
    maturityScore: number;
    pendingCount: number;
    nextPendingItem?: { text: string; section: string; tags?: string[] } | null;
    auditFindings: RoadmapAuditFinding[];
  };
  dispatchContext: {
    dispatchReadiness: DispatchReadiness;
    dispatchReadinessExplanation?: string | null;
    recommendedAction: string;
    blockingReasons: string[];
    pendingItemCount: number;
    nextPendingItemText?: string | null;
    topValueItem: PortfolioPendingItemValue | null;
  };
}

export interface OperationsPromptRefineRequest {
  repoName: string;
  roadmapPath?: string;
  selectedTaskText?: string;
  selectedTaskSection?: string;
  additionalConstraints?: string[];
  emphasisAreas?: string[];
  operatorInstructions?: string;
}

export interface OperationsPromptRefineWarning {
  severity: 'critical' | 'warning' | 'info';
  code: string;
  message: string;
}

export interface OperationsPromptRefineResult {
  runId?: string;
  createdAt?: string;
  packet: CopilotTaskPacket;
  refinedPrompt: string;
  warnings: OperationsPromptRefineWarning[];
  applied: {
    selectedTaskText: string;
    selectedTaskSection: string;
    additionalConstraints: string[];
    emphasisAreas: string[];
    operatorInstructions?: string;
  };
}

export interface OperationsPromptHistoryItem {
  runId: string;
  createdAt: string;
  repoName: string;
  selectedItemText: string;
  selectedItemSection: string;
  selectionSource: 'value-ranked' | 'roadmap-order' | 'operator-selected';
  operatorInstructions?: string;
  additionalConstraints: string[];
  emphasisAreas: string[];
  warningCount: number;
  dispatchCount: number;
  latestDispatchAt?: string | null;
  dispatchRecords: OperationsPromptDispatchRecord[];
}

export interface OperationsPromptDispatchRecord {
  promptRefinementRunId: string;
  dispatchRunId: string;
  repoName: string;
  githubRepo: string;
  status: 'started' | 'failed';
  startedAt: string;
  recordedAt: string;
  localPath?: string | null;
  baseBranch?: string | null;
}

// --- Release 1.9: AI documentation improvement cycles ---

export type AiDocType = 'readme' | 'roadmap';
export type AiDocProvider = 'auto' | 'heuristic' | 'openai' | 'anthropic';

export interface AiDocTemplate {
  id: string;
  label: string;
  summary: string;
  guidance: string;
  requiredSections: string[];
}

export interface AiDocTemplatesResult {
  readmeTemplates: AiDocTemplate[];
  roadmapTemplates: AiDocTemplate[];
}

/**
 * Token usage and cost for one improvement preview.
 *
 * Every count is nullable and null means *unmeasured*, never zero — a zero here
 * would render as "this run was free", which is a different claim. `source` and
 * `costBasis` say which kind of blank it is, so a surface can explain itself:
 *
 *   source: provider-usage   real counts came back from the model
 *           absent           the model answered and reported nothing (a defect)
 *           call-failed      the call errored; usage cannot be known
 *           not-applicable   no model was called (offline heuristic provider)
 */
export interface AiDocUsage {
  inputTokens: number | null;
  outputTokens: number | null;
  totalTokens: number | null;
  measured: boolean;
  source: 'provider-usage' | 'absent' | 'call-failed' | 'not-applicable';
  costUsd: number | null;
  costBasis: string;
}

export interface AiDocImprovePreviewRequest {
  repoName: string;
  docType: AiDocType;
  templateId?: string;
  customPrompt?: string;
  provider?: AiDocProvider;
  /** Optional inline content; when omitted the backend resolves it from the roadmap cache or portfolio index. */
  currentContent?: string;
  path?: string;
}

export interface AiDocImprovePreviewResult {
  previewId: string;
  repoName: string;
  docType: AiDocType;
  providerId: string;
  modelId?: string | null;
  templateId: string;
  customPrompt?: string | null;
  currentContent: string;
  proposedContent: string;
  changeSummary: string[];
  estimatedScore: {
    before: number;
    after: number;
    delta: number;
  };
  usage?: AiDocUsage | null;
  warnings: string[];
  generatedAt: string;
}

export interface AiDocImprovementHistoryItem {
  previewId: string;
  createdAt: string;
  repoName: string;
  docType: AiDocType;
  providerId: string;
  modelId?: string | null;
  templateId: string;
  customPrompt?: string | null;
  scoreBefore: number;
  scoreAfter: number;
  scoreDelta: number;
  changeSummary: string[];
  warningCount: number;
  /** Named to match the agent-run metrics of the same name so the two series join without translation. Null = unmeasured. */
  inputTokens?: number | null;
  outputTokens?: number | null;
  tokenUsage?: number | null;
  apiSpendUsd?: number | null;
  usageMeasured?: boolean;
  usageSource?: AiDocUsage['source'];
  costBasis?: string;
  applied: boolean;
  /** 'apply' records are written by the explicit apply action; preview records have no recordType. */
  recordType?: 'preview' | 'apply';
  backupPath?: string | null;
}

export interface AiDocImproveApplyRequest {
  repoName: string;
  docType: AiDocType;
  /** The operator-approved content to write. Apply never generates content itself. */
  proposedContent: string;
  previewId?: string;
  /** Optional explicit target file path; when omitted the backend resolves it from the roadmap cache or portfolio index. */
  path?: string;
}

export interface AiDocImproveApplyResult {
  applyId: string;
  repoName: string;
  docType: AiDocType;
  targetPath: string;
  backupPath: string | null;
  restoreMetadataPath: string | null;
  originalExisted: boolean;
  previewId: string | null;
  appliedAt: string;
}

// --- Release 2.0: Agent run monitoring and Actions-gated merge readiness ---

export type AgentRunStatus = 'dispatched' | 'active' | 'completed' | 'failed' | 'blocked';

export interface AgentRunMetrics {
  dispatchedAt?: string | null;
  agentStartedAt?: string | null;
  agentCompletedAt?: string | null;
  timeToDeliverSeconds?: number | null;
  promptCount?: number | null;
  retries?: number | null;
  tokenUsage?: number | null;
  apiSpendUsd?: number | null;
  workUnitsEstimated?: number | null;
  workUnitsActual?: number | null;
  unitsRemainingObserved?: number | null;
  creditPromptSeen?: boolean | null;
  humanReviewMinutes?: number | null;
}

export interface AgentRunActionsState {
  status: string;
  conclusion?: string | null;
  workflowName?: string | null;
  runUrl?: string | null;
  observedAt: string;
}

export interface AgentRunAssociation {
  matchedBy: string[];
  candidateCount: number;
  associatedAt: string;
}

export interface AgentRun {
  runId: string;
  repoName: string;
  repoId?: string | null;
  githubRepo?: string | null;
  localPath?: string | null;
  dispatchRunId?: string | null;
  promptRefinementRunId?: string | null;
  selectedTaskText?: string | null;
  selectedTaskSection?: string | null;
  plannedReleaseName?: string | null;
  plannedPhaseName?: string | null;
  workUnitsEstimateSource?: string | null;
  providerTool: string;
  branch?: string | null;
  baseBranch?: string | null;
  prUrl?: string | null;
  prNumber?: number | null;
  prState?: 'open' | 'closed' | 'merged' | null;
  prDraft?: boolean | null;
  status: AgentRunStatus;
  outcome?: string | null;
  createdAt: string;
  updatedAt: string;
  lastRefreshAt?: string | null;
  metrics?: AgentRunMetrics | null;
  actions?: AgentRunActionsState | null;
  association?: AgentRunAssociation | null;
}

export interface AgentRunEvent {
  schemaVersion: string;
  eventId: string;
  timestamp: string;
  eventType: string;
  runId: string;
  repoName: string;
  actor: string;
  summary: string;
  data?: Record<string, unknown> | null;
}

export interface AgentRunsResult {
  items: AgentRun[];
  count: number;
  byStatus: Record<string, number>;
}

export interface AgentRunDetailResult {
  run: AgentRun;
  events: AgentRunEvent[];
}

export interface AgentRunRefreshResult {
  run: AgentRun;
  association: AgentRunAssociation;
  pullRequestFound: boolean;
  validationEvent?: string | null;
  refreshedAt: string;
}

export interface MergeReadinessBlocker {
  code: string;
  message: string;
  source: 'agent-run-ledger' | 'github' | 'local-git' | 'assessment' | string;
}

export interface MergeReadinessEvidence {
  prState?: string | null;
  prDraft?: boolean;
  mergeable?: boolean | null;
  mergeableState?: string | null;
  actionsStatus?: string;
  actionsConclusion?: string;
  actionsWorkflowName?: string;
  localDirtyCount?: number;
  auditBlockerCount?: number;
}

export interface MergeReadinessResult {
  repoId: string;
  repoName: string;
  runId?: string | null;
  prUrl?: string | null;
  prNumber?: number | null;
  ready: boolean;
  blockers: MergeReadinessBlocker[];
  evidence: MergeReadinessEvidence;
  evaluatedAt: string;
}

export interface MergeReadinessMergeResult {
  merged: boolean;
  sha: string;
  message: string;
  runId: string;
  evaluation: MergeReadinessResult;
}
