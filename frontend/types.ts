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
  owner?: string;
  visibility?: string;
  language?: string | null;
  topics?: string[];
  
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

export type OperationType = 'init' | 'update' | 'sync' | 'export' | 'archive';

export interface GithubInsightsMeta {
  totalRepos: number;
  fetchedRepos: number;
  rateLimit?: {
    remaining: number;
    limit: number;
    reset: number;
  } | null;
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
