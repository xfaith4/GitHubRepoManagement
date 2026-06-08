### BEGIN FILE: Repo-Reconciliation-Dashboard.ps1
<#!
.SYNOPSIS
    Reconciles local repository folders with GitHub repositories to identify matches, discrepancies, and duplicates.

.DESCRIPTION
    This script inventories local Git repositories and optional non-Git project folders, compares them with GitHub repositories,
    and generates reports including potential duplicates. It includes logging, defensive validation, and HTML/CSV/JSON outputs.

.PARAMETER LocalRoots
    Array of local root paths to scan for repositories. Default: @('G:\Development')

.PARAMETER GitHubOwner
    GitHub username or organization name. If omitted, GitHub inventory is skipped.

.PARAMETER OwnerType
    Type of GitHub owner: 'User', 'Org', or 'Auto' (default). Auto attempts User first, then Org.

.PARAMETER OutDir
    Output directory for reports. Default: [LocalRoots[0]]\Repo_reconciliation-dashboard\_repo_reconciliation

.PARAMETER LogPath
    Optional path to write detailed log file. If omitted, only console output is used.

.PARAMETER IncludeNonGitFolders
    Include non-Git folders in inventory. Default: $true

.PARAMETER OpenHtmlReport
    Automatically open HTML report in the default browser. Default: $true

.PARAMETER IgnoreDirNames
    Directory names to ignore during scanning. Default: common build/dependency folders.

.PARAMETER IgnorePathRegex
    Array of regex patterns for paths to ignore. Default: .git directories.

.PARAMETER MaxDepth
    Maximum folder depth to scan. Default: 3

.EXAMPLE
    .\Repo-Reconciliation-Dashboard.ps1 -LocalRoots @('D:\repos','E:\projects') -GitHubOwner myorg -LogPath 'C:\logs\reconciliation.log'
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$LocalRoots = @('G:\Development'),

    [Parameter()]
    [string]$GitHubOwner,

    [Parameter()]
    [ValidateSet('User', 'Org', 'Auto')]
    [string]$OwnerType = 'Auto',

    [Parameter()]
    [string]$OutDir,

    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [switch]$IncludeNonGitFolders = $true,

    [Parameter()]
    [switch]$OpenHtmlReport = $true,

    [Parameter()]
    [switch]$LoadFunctionsOnly,

    [Parameter()]
    [string[]]$IgnoreDirNames = @(
        'node_modules', 'vendor', 'dist', 'build', 'out', '.vs', '.idea', '.vscode',
        'bin', 'obj', '.venv', 'venv', '__pycache__', '.next', '.pytest_cache'
    ),

    [Parameter()]
    [string[]]$IgnorePathRegex = @(
        '[/\\]\.git([/\\]|$)'
    ),

    [Parameter()]
    [ValidateRange(1, 20)]
    [int]$MaxDepth = 3
)

#Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($LocalRoots.Count -eq 0) {
    throw 'LocalRoots parameter cannot be empty.'
}

if (-not $OutDir) {
    if ($LoadFunctionsOnly) {
        $OutDir = [string]$LocalRoots[0]
    }
    else {
    $OutDir = Join-Path -Path (Join-Path -Path $LocalRoots[0] -ChildPath 'Repo_reconciliation-dashboard') -ChildPath '_repo_reconciliation'
    }
}

$script:SIMILARITY_SCORE_THRESHOLD         = 65
$script:SIMILARITY_REPO_NAME_BONUS         = 50
$script:SIMILARITY_FOLDER_NAME_BONUS       = 30
$script:SIMILARITY_DIR_BONUS_PER_MATCH     = 4
$script:SIMILARITY_DIR_BONUS_MAX           = 20
$script:SIMILARITY_KEY_FILE_BONUS_PER_MATCH= 5
$script:SIMILARITY_KEY_FILE_BONUS_MAX      = 20
$script:SIMILARITY_EXT_BONUS_PER_MATCH     = 2
$script:SIMILARITY_EXT_BONUS_MAX           = 10
$script:GH_QUERY_LIMIT                     = 500
$script:DIR_FINGERPRINT_MAX_FILES          = 200
$script:OWNER_VALIDATION_PATTERN           = '^[a-zA-Z0-9_-]+$'
$script:LogFile                            = $LogPath
$script:StartTime                          = Get-Date
$script:ExecutionStopwatch                 = [System.Diagnostics.Stopwatch]::StartNew()
$script:ScannedDirectoryCount              = 0
$script:RepositoriesFound                  = 0

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $levelStr  = $Level.ToUpper().PadRight(7)
    $logMsg    = "[$timestamp] [$levelStr] $Message"

    switch ($Level) {
        'Error' {
            Write-Host $logMsg -ForegroundColor Red
            if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $logMsg -Encoding UTF8 }
        }
        'Warning' {
            Write-Warning $Message
            if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $logMsg -Encoding UTF8 }
        }
        'Debug' {
            Write-Debug $Message
            if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $logMsg -Encoding UTF8 }
        }
        default {
            Write-Host $logMsg -ForegroundColor Cyan
            if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $logMsg -Encoding UTF8 }
        }
    }
}

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Test-ValidGitHubOwner {
    param([Parameter(Mandatory = $true)][string]$Owner)

    if ($Owner -notmatch $script:OWNER_VALIDATION_PATTERN) {
        throw "Invalid GitHub owner name '$Owner'. Allowed characters: letters, numbers, hyphen, underscore."
    }
}

function Test-RegexPattern {
    param([Parameter(Mandatory = $true)][string]$Pattern)

    try {
        [void][regex]::new($Pattern)
        return $true
    }
    catch {
        Write-Log "Invalid regex pattern '$Pattern': $_" -Level Warning
        return $false
    }
}

function Get-NormalizedExistingPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved)) {
        throw "Path does not exist: $resolved"
    }

    return $resolved.TrimEnd('\\')
}

function Get-ElapsedTimeString {
    $elapsed = $script:ExecutionStopwatch.Elapsed
    return '{0:00}:{1:00}:{2:00}' -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds
}

function Test-IgnoredPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$RegexList
    )

    foreach ($rx in $RegexList) {
        try {
            if ($Path -match $rx) {
                return $true
            }
        }
        catch {
            Write-Log "Regex match error with pattern '$rx' on '$Path': $_" -Level Debug
        }
    }

    return $false
}

### BEGIN: Replace Get-DirectoryFingerprint
function Get-DirectoryFingerprint {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$IgnoreDirNames,
        [Parameter(Mandatory = $true)][string[]]$IgnorePathRegex,
        [int]$MaxFiles = $script:DIR_FINGERPRINT_MAX_FILES
    )

    try {
        $files = @(
            Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    $full = $_.FullName
                    $nameSegments = $full -split '[\\/]'
                    $hasIgnoredDir = $false
                    foreach ($segment in $nameSegments) {
                        if ($IgnoreDirNames -contains $segment) {
                            $hasIgnoredDir = $true
                            break
                        }
                    }
                    (-not $hasIgnoredDir) -and (-not (Test-IgnoredPath -Path $full -RegexList $IgnorePathRegex))
                } |
                Sort-Object FullName |
                Select-Object -First $MaxFiles
        )

        $extensions = @(
            $files |
                ForEach-Object { if ($_.Extension) { $_.Extension.ToLowerInvariant() } } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Group-Object -NoElement |
                Sort-Object Count -Descending |
                Select-Object -First 10 |
                ForEach-Object { $_.Name }
        )

        $topLevelDirs = @(
            Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name |
                Sort-Object |
                Select-Object -First 20
        )

        $keyFiles = @(
            $files |
                Where-Object {
                    $_.Name -match '^(README|package|tsconfig|requirements|pyproject|Cargo|go\.mod|pom|build|docker-compose|Dockerfile|Makefile|\.env\.example|vite\.config|next\.config|tailwind\.config|webpack)'
                } |
                Select-Object -ExpandProperty Name -Unique |
                Sort-Object
        )

        $fileCount = @($files).Count
        $totalBytes = [int64]0
        if ($fileCount -gt 0) {
            $measure = @($files) | Measure-Object -Property Length -Sum
            if ($null -ne $measure.Sum) {
                $totalBytes = [int64]$measure.Sum
            }
        }

        return [pscustomobject]@{
            SampleFileCount = $fileCount
            TotalFileBytes  = $totalBytes
            Extensions      = @($extensions)
            TopLevelDirs    = @($topLevelDirs)
            KeyFiles        = @($keyFiles)
        }
    }
    catch {
        Write-Log "Error generating fingerprint for '$Path': $_" -Level Warning
        return [pscustomobject]@{
            SampleFileCount = 0
            TotalFileBytes  = [int64]0
            Extensions      = @()
            TopLevelDirs    = @()
            KeyFiles        = @()
        }
    }
}
### END: Replace Get-DirectoryFingerprint

function Get-LocalFolderInventory {
    param(
        [Parameter(Mandatory = $true)][string[]]$Roots,
        [Parameter(Mandatory = $true)][string[]]$IgnoreDirNames,
        [Parameter(Mandatory = $true)][string[]]$IgnorePathRegex,
        [Parameter(Mandatory = $true)][int]$MaxDepth,
        [Parameter()]
        [switch]$IncludeNonGitFolders
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($root in $Roots) {
        try {
            $resolvedRoot = Get-NormalizedExistingPath -Path $root
        }
        catch {
            Write-Log "Skipping invalid root '$root': $_" -Level Warning
            continue
        }

        Write-Log "Scanning local root: $resolvedRoot"
        Write-Log "Scan settings for '$resolvedRoot': MaxDepth=$MaxDepth, IncludeNonGitFolders=$($IncludeNonGitFolders.IsPresent), IgnoreDirNames=$($IgnoreDirNames.Count), IgnorePathRegex=$($IgnorePathRegex.Count)"

        $queue = New-Object System.Collections.Generic.Queue[object]
        $queue.Enqueue([pscustomobject]@{ Path = $resolvedRoot; Depth = 0 })
        Write-Log "Root queued for traversal: $resolvedRoot"

        while ($queue.Count -gt 0) {
            $item = $queue.Dequeue()
            $currentPath = $item.Path
            $depth = $item.Depth

            if ($depth -gt $MaxDepth) {
                Write-Log "Skipping path beyond MaxDepth ($MaxDepth): $currentPath" -Level Debug
                continue
            }
            if (Test-IgnoredPath -Path $currentPath -RegexList $IgnorePathRegex) {
                Write-Log "Skipping ignored path: $currentPath" -Level Debug
                continue
            }

            if ($depth -le 1) {
                Write-Log "Inspecting depth $depth path: $currentPath"
            }

            try {
                $childDirs = @(Get-ChildItem -LiteralPath $currentPath -Directory -Force -ErrorAction SilentlyContinue)
            }
            catch {
                Write-Log "Error reading directory '$currentPath': $_" -Level Debug
                continue
            }

            Write-Log "Found $($childDirs.Count) child directories under '$currentPath'" -Level Debug

            foreach ($child in $childDirs) {
                if ($IgnoreDirNames -contains $child.Name) {
                    Write-Log "Skipping ignored directory name '$($child.Name)' at '$($child.FullName)'" -Level Debug
                    continue
                }

                $script:ScannedDirectoryCount++
                if (($script:ScannedDirectoryCount % 50) -eq 0) {
                    Write-Log "Scanned $($script:ScannedDirectoryCount) directories so far... queue remaining: $($queue.Count)"
                }

                $fullPath = $child.FullName
                if (Test-IgnoredPath -Path $fullPath -RegexList $IgnorePathRegex) {
                    Write-Log "Skipping ignored child path: $fullPath" -Level Debug
                    continue
                }

                $gitPath   = Join-Path -Path $fullPath -ChildPath '.git'
                $isGitRepo = Test-Path -LiteralPath $gitPath

                if ($isGitRepo -or $IncludeNonGitFolders) {
                    if ($isGitRepo) {
                        Write-Log "Repository candidate detected: $fullPath"
                    }
                    else {
                        Write-Log "Including non-git folder for inventory: $fullPath" -Level Debug
                    }

                    Write-Log "Fingerprinting folder: $fullPath" -Level Debug
                    $fingerprint = Get-DirectoryFingerprint -Path $fullPath -IgnoreDirNames $IgnoreDirNames -IgnorePathRegex $IgnorePathRegex

                    $originUrl      = $null
                    $branch         = $null
                    $statusShort    = @()
                    $lastCommitDate = $null
                    $lastCommitMessage = $null
                    $lastCommitAuthor = $null
                    $commitsLastWeek = 0
                    $commitsLastMonth = 0
                    $repoNameGuess  = $child.Name
                    $ownerGuess     = $null

                    if ($isGitRepo -and (Test-CommandExists -Name 'git')) {
                        Write-Log "Collecting git metadata for: $fullPath" -Level Debug
                        try {
                            $branch = (& git -C $fullPath branch --show-current 2>$null)
                            if ($LASTEXITCODE -ne 0) { $branch = $null }
                        }
                        catch {
                            Write-Log "Git branch query error for '$fullPath': $_" -Level Debug
                            $branch = $null
                        }

                        try {
                            $originUrl = (& git -C $fullPath remote get-url origin 2>$null)
                            if ($LASTEXITCODE -ne 0) { $originUrl = $null }
                        }
                        catch {
                            Write-Log "Git origin query error for '$fullPath': $_" -Level Debug
                            $originUrl = $null
                        }

                        try {
                            $lastCommitDate = (& git -C $fullPath log -1 --format=%cI 2>$null)
                            if ($LASTEXITCODE -ne 0) { $lastCommitDate = $null }
                        }
                        catch {
                            Write-Log "Git log query error for '$fullPath': $_" -Level Debug
                            $lastCommitDate = $null
                        }

                        try {
                            $statusShort = @(& git -C $fullPath status --short 2>$null)
                            if ($LASTEXITCODE -ne 0) { $statusShort = @() }
                        }
                        catch {
                            Write-Log "Git status query error for '$fullPath': $_" -Level Debug
                            $statusShort = @()
                        }

                        try {
                            $lastCommitMessage = (& git -C $fullPath log -1 --format=%s 2>$null)
                            if ($LASTEXITCODE -ne 0) { $lastCommitMessage = $null }
                        }
                        catch {
                            Write-Log "Git last commit message query error for '$fullPath': $_" -Level Debug
                            $lastCommitMessage = $null
                        }

                        try {
                            $lastCommitAuthor = (& git -C $fullPath log -1 --format=%an 2>$null)
                            if ($LASTEXITCODE -ne 0) { $lastCommitAuthor = $null }
                        }
                        catch {
                            Write-Log "Git last commit author query error for '$fullPath': $_" -Level Debug
                            $lastCommitAuthor = $null
                        }

                        try {
                            $weekCountRaw = (& git -C $fullPath rev-list --count --since="7 days ago" HEAD 2>$null)
                            if ($LASTEXITCODE -eq 0 -and $weekCountRaw -match '^\d+$') { $commitsLastWeek = [int]$weekCountRaw }
                        }
                        catch {
                            Write-Log "Git weekly commit count query error for '$fullPath': $_" -Level Debug
                            $commitsLastWeek = 0
                        }

                        try {
                            $monthCountRaw = (& git -C $fullPath rev-list --count --since="30 days ago" HEAD 2>$null)
                            if ($LASTEXITCODE -eq 0 -and $monthCountRaw -match '^\d+$') { $commitsLastMonth = [int]$monthCountRaw }
                        }
                        catch {
                            Write-Log "Git monthly commit count query error for '$fullPath': $_" -Level Debug
                            $commitsLastMonth = 0
                        }
                    }

                    if ($originUrl -and ($originUrl -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)(\.git)?$')) {
                        $ownerGuess    = $matches['owner']
                        $repoNameGuess = $matches['repo']
                    }

                    $modifiedCount = 0
                    $untrackedCount = 0
                    $otherStatusCount = 0
                    foreach ($line in @($statusShort)) {
                        if ([string]::IsNullOrWhiteSpace($line)) { continue }
                        if ($line.StartsWith('??')) {
                            $untrackedCount++
                        }
                        elseif ($line.Length -ge 2) {
                            $modifiedCount++
                        }
                        else {
                            $otherStatusCount++
                        }
                    }

                    $results.Add([pscustomobject]@{
                        LocalRoot        = $resolvedRoot
                        FolderName       = $child.Name
                        LocalPath        = $fullPath
                        IsGitRepo        = $isGitRepo
                        GitOriginUrl     = $originUrl
                        GitOwnerGuess    = $ownerGuess
                        GitRepoName      = $repoNameGuess
                        CurrentBranch    = $branch
                        LastCommitDate   = $lastCommitDate
                        LastCommitMessage = $lastCommitMessage
                        LastCommitAuthor = $lastCommitAuthor
                        CommitsLastWeek  = $commitsLastWeek
                        CommitsLastMonth = $commitsLastMonth
                        ModifiedCount    = $modifiedCount
                        UntrackedCount   = $untrackedCount
                        OtherStatusCount = $otherStatusCount
                        Fingerprint      = $fingerprint
                    })

                    $script:RepositoriesFound++
                    if ($isGitRepo) {
                        Write-Log "Found repo #$($script:RepositoriesFound): $($child.Name) (Branch: $branch, Modified: $modifiedCount, Untracked: $untrackedCount)"
                    }
                    elseif (($script:RepositoriesFound % 25) -eq 0) {
                        Write-Log "Inventory items collected so far: $($results.Count)"
                    }
                }

                if ($depth + 1 -le $MaxDepth) {
                    $queue.Enqueue([pscustomobject]@{ Path = $fullPath; Depth = ($depth + 1) })
                    if ($depth -lt 1) {
                        Write-Log "Queued child path for depth $($depth + 1): $fullPath" -Level Debug
                    }
                }
            }
        }

        Write-Log "Completed scan for root '$resolvedRoot'. Inventory items so far: $($results.Count)"
    }

    return $results.ToArray()
}

function Get-GitHubRepoInventory {
    param(
        [Parameter()]
        [string]$Owner,

        [Parameter()]
        [ValidateSet('User', 'Org', 'Auto')]
        [string]$OwnerType = 'Auto'
    )

    if (-not $Owner) {
        Write-Log 'GitHub owner not specified; skipping GitHub inventory.'
        return @()
    }

    Test-ValidGitHubOwner -Owner $Owner

    if (-not (Test-CommandExists -Name 'gh')) {
        throw 'GitHub CLI (gh) not found in PATH. Install gh or omit -GitHubOwner.'
    }

    Write-Log "Querying GitHub for owner: $Owner"

    $repoList = @()
    $jsonFields = 'name,nameWithOwner,isPrivate,isArchived,defaultBranchRef,updatedAt,url,description,sshUrl'

    function Invoke-GhRepoList {
        param([Parameter(Mandatory = $true)][string]$OwnerValue)

        $repoJson = & gh repo list $OwnerValue --limit $script:GH_QUERY_LIMIT --json $jsonFields 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "gh repo list failed for owner '$OwnerValue'."
        }

        $jsonText = ($repoJson -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($jsonText)) {
            return @()
        }

        return @($jsonText | ConvertFrom-Json)
    }

    if ($OwnerType -eq 'User' -or $OwnerType -eq 'Auto') {
        try {
            $repoList = Invoke-GhRepoList -OwnerValue $Owner
        }
        catch {
            if ($OwnerType -eq 'User') {
                Write-Log "Failed to query GitHub user repos for '$Owner': $_" -Level Error
                throw
            }
            Write-Log "User repo query failed for '$Owner'; will try org mode. $_" -Level Debug
        }
    }

    if ((@($repoList).Count -eq 0) -and ($OwnerType -eq 'Org' -or $OwnerType -eq 'Auto')) {
        try {
            $repoList = Invoke-GhRepoList -OwnerValue $Owner
        }
        catch {
            Write-Log "Failed to query GitHub repos for '$Owner': $_" -Level Warning
            return @()
        }
    }

    return @(
        $repoList | ForEach-Object {
            [pscustomobject]@{
                Owner         = $Owner
                RepoName      = $_.name
                NameWithOwner = $_.nameWithOwner
                IsPrivate     = $_.isPrivate
                IsArchived    = $_.isArchived
                DefaultBranch = if ($_.defaultBranchRef) { $_.defaultBranchRef.name } else { $null }
                UpdatedAt     = $_.updatedAt
                Url           = $_.url
                SshUrl        = $_.sshUrl
                Description   = $_.description
            }
        }
    )
}

function Get-SimilarityScore {
    param(
        [Parameter(Mandatory = $true)][object]$LocalA,
        [Parameter(Mandatory = $true)][object]$LocalB
    )

    # Different known remote origins are a definitive signal these are not duplicates
    if ($LocalA.GitOriginUrl -and $LocalB.GitOriginUrl -and ($LocalA.GitOriginUrl -ne $LocalB.GitOriginUrl)) {
        return 0
    }

    $score = 0

    if ($LocalA.GitRepoName -and $LocalB.GitRepoName -and ($LocalA.GitRepoName -eq $LocalB.GitRepoName)) {
        $score += $script:SIMILARITY_REPO_NAME_BONUS
    }

    if ($LocalA.FolderName -eq $LocalB.FolderName) {
        $score += $script:SIMILARITY_FOLDER_NAME_BONUS
    }

    $dirsA = @($LocalA.Fingerprint.TopLevelDirs)
    $dirsB = @($LocalB.Fingerprint.TopLevelDirs)
    $commonDirs = @($dirsA | Where-Object { $dirsB -contains $_ })
    $score += [Math]::Min(($commonDirs.Count * $script:SIMILARITY_DIR_BONUS_PER_MATCH), $script:SIMILARITY_DIR_BONUS_MAX)

    $keysA = @($LocalA.Fingerprint.KeyFiles)
    $keysB = @($LocalB.Fingerprint.KeyFiles)
    $commonKeys = @($keysA | Where-Object { $keysB -contains $_ })
    $score += [Math]::Min(($commonKeys.Count * $script:SIMILARITY_KEY_FILE_BONUS_PER_MATCH), $script:SIMILARITY_KEY_FILE_BONUS_MAX)

    $extA = @($LocalA.Fingerprint.Extensions | ForEach-Object { ($_ -split ':')[0] })
    $extB = @($LocalB.Fingerprint.Extensions | ForEach-Object { ($_ -split ':')[0] })
    $commonExt = @($extA | Where-Object { $extB -contains $_ })
    $score += [Math]::Min(($commonExt.Count * $script:SIMILARITY_EXT_BONUS_PER_MATCH), $script:SIMILARITY_EXT_BONUS_MAX)

    return $score
}

function Compare-LocalAndGitHub {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$LocalItems,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$GitHubItems
    )

    $comparisons = New-Object System.Collections.Generic.List[object]

    foreach ($local in $LocalItems) {
        $exact = $null
        $matchReason = $null

        if ($local.GitOriginUrl) {
            $exact = $GitHubItems |
                Where-Object {
                    ($_.Url -eq $local.GitOriginUrl) -or
                    ($_.SshUrl -eq $local.GitOriginUrl) -or
                    ($local.GitOwnerGuess -and $_.NameWithOwner -eq ('{0}/{1}' -f $local.GitOwnerGuess, $local.GitRepoName))
                } |
                Select-Object -First 1

            if ($exact) { $matchReason = 'OriginUrl' }
        }

        if (-not $exact -and $local.GitRepoName) {
            $exact = $GitHubItems | Where-Object { $_.RepoName -eq $local.GitRepoName } | Select-Object -First 1
            if ($exact) { $matchReason = 'RepoName' }
        }

        $status = if ($exact) { 'Matched' } else { 'LocalOnly' }

        $comparisons.Add([pscustomobject]@{
            Status          = $status
            MatchReason     = $matchReason
            LocalRoot       = $local.LocalRoot
            LocalPath       = $local.LocalPath
            FolderName      = $local.FolderName
            IsGitRepo       = $local.IsGitRepo
            GitOriginUrl    = $local.GitOriginUrl
            GitRepoName     = $local.GitRepoName
            CurrentBranch   = $local.CurrentBranch
            LastCommitDate  = $local.LastCommitDate
            ModifiedCount   = $local.ModifiedCount
            UntrackedCount  = $local.UntrackedCount
            GitHubRepo      = if ($exact) { $exact.NameWithOwner } else { $null }
            GitHubUrl       = if ($exact) { $exact.Url } else { $null }
            GitHubUpdatedAt = if ($exact) { $exact.UpdatedAt } else { $null }
            GitHubArchived  = if ($exact) { $exact.IsArchived } else { $null }
        })
    }

    foreach ($ghRepo in $GitHubItems) {
        $matched = $comparisons | Where-Object { $_.GitHubRepo -eq $ghRepo.NameWithOwner } | Select-Object -First 1
        if (-not $matched) {
            $comparisons.Add([pscustomobject]@{
                Status          = 'GitHubOnly'
                MatchReason     = $null
                LocalRoot       = $null
                LocalPath       = $null
                FolderName      = $null
                IsGitRepo       = $null
                GitOriginUrl    = $null
                GitRepoName     = $null
                CurrentBranch   = $null
                LastCommitDate  = $null
                ModifiedCount   = $null
                UntrackedCount  = $null
                GitHubRepo      = $ghRepo.NameWithOwner
                GitHubUrl       = $ghRepo.Url
                GitHubUpdatedAt = $ghRepo.UpdatedAt
                GitHubArchived  = $ghRepo.IsArchived
            })
        }
    }

    return $comparisons.ToArray()
}

function Get-PotentialLocalDuplicates {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$LocalItems)

    $dupes = New-Object System.Collections.Generic.List[object]
    $itemCount = ($LocalItems | Measure-Object).Count

    for ($i = 0; $i -lt $itemCount; $i++) {
        for ($j = $i + 1; $j -lt $itemCount; $j++) {
            $a = $LocalItems[$i]
            $b = $LocalItems[$j]

            $score = Get-SimilarityScore -LocalA $a -LocalB $b
            if ($score -lt $script:SIMILARITY_SCORE_THRESHOLD) {
                continue
            }

            $dupeType = if ($a.GitOriginUrl -and ($a.GitOriginUrl -eq $b.GitOriginUrl)) {
                'SameOrigin'
            } elseif ($a.GitRepoName -and $b.GitRepoName -and ($a.GitRepoName -eq $b.GitRepoName)) {
                'SameName'
            } else {
                'Structural'
            }

            $confidence = switch ($dupeType) {
                'SameOrigin' { 'High' }
                'SameName'   { 'Medium' }
                default      { 'Low' }
            }

            $dupes.Add([pscustomobject]@{
                DuplicateType   = $dupeType
                Confidence      = $confidence
                SimilarityScore = $score
                RepoNameA       = $a.GitRepoName
                PathA           = $a.LocalPath
                RepoNameB       = $b.GitRepoName
                PathB           = $b.LocalPath
                OriginA         = $a.GitOriginUrl
                OriginB         = $b.GitOriginUrl
                BranchA         = $a.CurrentBranch
                BranchB         = $b.CurrentBranch
                LastCommitA     = $a.LastCommitDate
                LastCommitB     = $b.LastCommitDate
                ModifiedA       = $a.ModifiedCount
                ModifiedB       = $b.ModifiedCount
            })
        }
    }

    return @($dupes.ToArray() | Sort-Object SimilarityScore -Descending)
}

function ConvertTo-HtmlTable {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Data,
        [Parameter(Mandatory = $true)][string[]]$Columns
    )

    Add-Type -AssemblyName System.Web

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<table>')
    [void]$sb.AppendLine('<thead><tr>')
    foreach ($col in $Columns) {
        [void]$sb.AppendLine("<th>$([System.Web.HttpUtility]::HtmlEncode($col))</th>")
    }
    [void]$sb.AppendLine('</tr></thead>')
    [void]$sb.AppendLine('<tbody>')

    foreach ($row in $Data) {
        [void]$sb.AppendLine('<tr>')
        foreach ($col in $Columns) {
            $prop = $row.PSObject.Properties[$col]
            if ($null -eq $prop -or $null -eq $prop.Value) {
                $value = ''
            }
            else {
                $value = [System.Web.HttpUtility]::HtmlEncode([string]$prop.Value)
            }
            [void]$sb.AppendLine("<td>$value</td>")
        }
        [void]$sb.AppendLine('</tr>')
    }

    [void]$sb.AppendLine('</tbody>')
    [void]$sb.AppendLine('</table>')
    return $sb.ToString()
}

function New-HtmlReport {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Comparison,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Duplicates,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$LocalItems,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$GitHubItems
    )

    Add-Type -AssemblyName System.Web

    $matched   = @($Comparison | Where-Object { $_.Status -eq 'Matched' })
    $localOnly = @($Comparison | Where-Object { $_.Status -eq 'LocalOnly' })
    $ghOnly    = @($Comparison | Where-Object { $_.Status -eq 'GitHubOnly' })

    $timestamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $elapsed    = (Get-Date) - $script:StartTime
    $durationStr = $elapsed.ToString('hh\\:mm\\:ss')

    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<title>Repo Reconciliation Dashboard</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #1f2937; background: #f3f4f6; }
h1, h2 { margin-bottom: 8px; color: #111827; }
.cardwrap { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 24px; }
.card { border: 1px solid #d1d5db; border-radius: 12px; padding: 16px; min-width: 220px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); background: white; }
.metric { font-size: 28px; font-weight: 700; color: #0066cc; }
.metadata { background: white; padding: 12px; border-radius: 8px; margin-bottom: 16px; }
table { border-collapse: collapse; width: 100%; margin: 12px 0 24px 0; background: white; }
th, td { border: 1px solid #e5e7eb; padding: 10px; text-align: left; vertical-align: top; }
th { background: #f9fafb; font-weight: 600; }
td { word-break: break-word; }
.small { color: #6b7280; font-size: 12px; }
code { background: #f3f4f6; padding: 2px 6px; border-radius: 4px; font-family: Consolas, monospace; }
.footer { color: #9ca3af; font-size: 11px; margin-top: 32px; border-top: 1px solid #e5e7eb; padding-top: 16px; }
</style>
</head>
<body>
<h1>Repo Reconciliation Dashboard</h1>
<div class="metadata">
  <p class="small"><strong>Generated:</strong> $([System.Web.HttpUtility]::HtmlEncode($timestamp))</p>
  <p class="small"><strong>Scan Duration:</strong> $durationStr</p>
  <p class="small"><strong>Report Type:</strong> Automated Repository Inventory and Reconciliation</p>
</div>

<div class="cardwrap">
  <div class="card"><div>Local folders scanned</div><div class="metric">$(@($LocalItems).Count)</div></div>
  <div class="card"><div>GitHub repos</div><div class="metric">$(@($GitHubItems).Count)</div></div>
  <div class="card"><div>Matched</div><div class="metric">$(@($matched).Count)</div></div>
  <div class="card"><div>Local only</div><div class="metric">$(@($localOnly).Count)</div></div>
  <div class="card"><div>GitHub only</div><div class="metric">$(@($ghOnly).Count)</div></div>
  <div class="card"><div>Potential duplicates</div><div class="metric">$(@($Duplicates).Count)</div></div>
</div>

<h2>Local Only</h2>
$(ConvertTo-HtmlTable -Data $localOnly -Columns @('FolderName','LocalPath','IsGitRepo','GitOriginUrl','CurrentBranch','LastCommitDate','ModifiedCount','UntrackedCount'))

<h2>GitHub Only</h2>
$(ConvertTo-HtmlTable -Data $ghOnly -Columns @('GitHubRepo','GitHubUrl','GitHubUpdatedAt','GitHubArchived'))

<h2>Matched</h2>
$(ConvertTo-HtmlTable -Data $matched -Columns @('FolderName','LocalPath','GitHubRepo','CurrentBranch','LastCommitDate','GitHubUpdatedAt','ModifiedCount','UntrackedCount'))

<h2>Potential Local Duplicates</h2>
<p class="small">Sorted by similarity score (threshold: $script:SIMILARITY_SCORE_THRESHOLD). Confidence: <strong>High</strong> = same remote origin, <strong>Medium</strong> = same repo name (different/no origin), <strong>Low</strong> = structural similarity only.</p>
$(ConvertTo-HtmlTable -Data $Duplicates -Columns @('Confidence','DuplicateType','SimilarityScore','RepoNameA','PathA','OriginA','RepoNameB','PathB','OriginB','BranchA','BranchB','LastCommitA','LastCommitB','ModifiedA','ModifiedB'))

<div class="footer">
  <p>Report generated by Repo Reconciliation Dashboard.</p>
</div>
</body>
</html>
"@

    Set-Content -LiteralPath $Path -Value $html -Encoding UTF8
    Write-Log "HTML report written to: $Path"
}

if ($LoadFunctionsOnly) {
    Write-Log 'LoadFunctionsOnly specified; skipping scan execution.' -Level Debug
    return
}

try {
    $null = New-Item -ItemType Directory -Path $OutDir -Force -ErrorAction Stop
    Write-Log "Output directory ready: $OutDir"

    if ($script:LogFile) {
        $logParent = Split-Path -Path $script:LogFile -Parent
        if ($logParent -and -not (Test-Path -LiteralPath $logParent)) {
            $null = New-Item -ItemType Directory -Path $logParent -Force -ErrorAction Stop
        }
        Write-Log "Logging to: $($script:LogFile)"
    }

    $validRegexPatterns = @($IgnorePathRegex | Where-Object { Test-RegexPattern -Pattern $_ })
    if ($validRegexPatterns.Count -ne $IgnorePathRegex.Count) {
        Write-Log 'Some invalid ignore regex patterns were skipped.' -Level Warning
    }
    $IgnorePathRegex = $validRegexPatterns

    Write-Log 'Starting repository inventory scan...'
    $localItems = Get-LocalFolderInventory -Roots $LocalRoots -IgnoreDirNames $IgnoreDirNames -IgnorePathRegex $IgnorePathRegex -MaxDepth $MaxDepth -IncludeNonGitFolders:$IncludeNonGitFolders
    Write-Log "Local inventory complete: $(@($localItems).Count) items found"

    $gitHubItems = @()
    if ($GitHubOwner) {
        try {
            $gitHubItems = Get-GitHubRepoInventory -Owner $GitHubOwner -OwnerType $OwnerType
            Write-Log "GitHub inventory complete: $(@($gitHubItems).Count) items found"
        }
        catch {
            Write-Log "GitHub inventory failed: $_" -Level Error
            Write-Log 'Continuing with local-only reconciliation...' -Level Warning
        }
    }

    Write-Log 'Performing repository comparison...'
    $comparison = Compare-LocalAndGitHub -LocalItems $localItems -GitHubItems $gitHubItems
    $duplicates = Get-PotentialLocalDuplicates -LocalItems $localItems

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $jsonPath = Join-Path -Path $OutDir -ChildPath ("repo-reconciliation_$($stamp).json")
    $csvPath = Join-Path -Path $OutDir -ChildPath ("repo-reconciliation_$($stamp).csv")
    $dupesCsvPath = Join-Path -Path $OutDir -ChildPath ("repo-duplicates_$($stamp).csv")
    $htmlPath = Join-Path -Path $OutDir -ChildPath ("repo-dashboard_$($stamp).html")

    try {
        [pscustomobject]@{
            GeneratedAt         = (Get-Date).ToString('o')
            ExecutionDurationMs = [int]((Get-Date) - $script:StartTime).TotalMilliseconds
            LocalRoots          = @($LocalRoots)
            GitHubOwner         = $GitHubOwner
            LocalItemsCount     = @($localItems).Count
            GitHubItemsCount    = @($gitHubItems).Count
            MatchedCount        = @($comparison | Where-Object { $_.Status -eq 'Matched' }).Count
            LocalOnlyCount      = @($comparison | Where-Object { $_.Status -eq 'LocalOnly' }).Count
            GitHubOnlyCount     = @($comparison | Where-Object { $_.Status -eq 'GitHubOnly' }).Count
            DuplicateCount            = @($duplicates).Count
            DuplicateSameOriginCount  = @($duplicates | Where-Object { $_.DuplicateType -eq 'SameOrigin' }).Count
            DuplicateSameNameCount    = @($duplicates | Where-Object { $_.DuplicateType -eq 'SameName' }).Count
            DuplicateStructuralCount  = @($duplicates | Where-Object { $_.DuplicateType -eq 'Structural' }).Count
            LocalItems          = @($localItems)
            GitHubItems         = @($gitHubItems)
            Comparison          = @($comparison)
            PotentialDuplicates = @($duplicates)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        Write-Log "JSON report exported: $jsonPath"
    }
    catch {
        Write-Log "Failed to export JSON report: $_" -Level Error
    }

    try {
        $comparison | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
        Write-Log "CSV report exported: $csvPath"
    }
    catch {
        Write-Log "Failed to export CSV report: $_" -Level Error
    }

    try {
        $duplicates | Export-Csv -LiteralPath $dupesCsvPath -NoTypeInformation -Encoding UTF8
        Write-Log "Duplicates CSV exported: $dupesCsvPath"
    }
    catch {
        Write-Log "Failed to export duplicates CSV: $_" -Level Error
    }

    try {
        New-HtmlReport -Path $htmlPath -Comparison $comparison -Duplicates $duplicates -LocalItems $localItems -GitHubItems $gitHubItems
    }
    catch {
        Write-Log "Failed to generate HTML report: $_" -Level Error
    }

    Write-Log ''
    Write-Log 'Repo reconciliation complete.'
    Write-Log 'Summary:'
    Write-Log "  Local folders scanned : $(@($localItems).Count)"
    Write-Log "  GitHub repos found    : $(@($gitHubItems).Count)"
    Write-Log "  Matched               : $(($comparison | Where-Object { $_.Status -eq 'Matched' } | Measure-Object).Count)"
    Write-Log "  Local only            : $(($comparison | Where-Object { $_.Status -eq 'LocalOnly' } | Measure-Object).Count)"
    Write-Log "  GitHub only           : $(($comparison | Where-Object { $_.Status -eq 'GitHubOnly' } | Measure-Object).Count)"
    Write-Log "  Potential duplicates  : $(@($duplicates).Count) (High: $(@($duplicates | Where-Object { $_.Confidence -eq 'High' }).Count), Medium: $(@($duplicates | Where-Object { $_.Confidence -eq 'Medium' }).Count), Low: $(@($duplicates | Where-Object { $_.Confidence -eq 'Low' }).Count))"
    Write-Log "  Execution time        : $(Get-ElapsedTimeString)"
    Write-Log ''
    Write-Log 'Output files:'
    Write-Log "  JSON      : $jsonPath"
    Write-Log "  CSV       : $csvPath"
    Write-Log "  Duplicates: $dupesCsvPath"
    Write-Log "  Dashboard : $htmlPath"

    if ($OpenHtmlReport) {
        try {
            if (Test-Path -LiteralPath $htmlPath) {
                Invoke-Item -LiteralPath $htmlPath
                Write-Log 'HTML report opened in default browser.'
            }
            else {
                Write-Log "HTML report file not found: $htmlPath" -Level Warning
            }
        }
        catch {
            Write-Log "Failed to open HTML report: $_" -Level Warning
        }
    }

    Write-Log 'Execution completed successfully.'
}
catch {
    Write-Log "Fatal error during execution: $_" -Level Error
    Write-Log "Execution time before failure: $(Get-ElapsedTimeString)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Debug
    exit 1
}
### END FILE: Repo-Reconciliati
