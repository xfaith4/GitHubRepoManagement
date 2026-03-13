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

export type OperationType = 'init' | 'update' | 'sync' | 'export' | 'archive' | 'docreview' | 'scan' | 'roadmap-scan' | 'roadmap-agent';

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
