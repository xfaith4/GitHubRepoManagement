#Requires -Modules Pester
<#
.SYNOPSIS
    Pester test suite for repo_reconciliation_dashboard.ps1 core functions.
.DESCRIPTION
    Covers edge cases for collection handling, validation, fingerprinting,
    similarity scoring, comparison, and duplicate detection.
    Run with: Invoke-Pester .\tests\repo_reconciliation.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:MainScript = "$PSScriptRoot\..\src\repo_reconciliation_dashboard.ps1"
    if (-not (Test-Path $script:MainScript)) {
        throw "Main script not found at: $script:MainScript"
    }
    . $script:MainScript -LoadFunctionsOnly
}

# ---------------------------------------------------------------------------
Describe 'Test-ValidGitHubOwner' {

    It 'accepts a valid alphanumeric username' {
        { Test-ValidGitHubOwner -Owner 'xfaith4' } | Should -Not -Throw
    }

    It 'accepts names with hyphens and underscores' {
        { Test-ValidGitHubOwner -Owner 'my-org_name' } | Should -Not -Throw
    }

    It 'rejects names with spaces' {
        { Test-ValidGitHubOwner -Owner 'my user' } | Should -Throw
    }

    It 'rejects names with special characters' {
        { Test-ValidGitHubOwner -Owner 'user@domain' } | Should -Throw
    }

    It 'rejects an empty string' {
        { Test-ValidGitHubOwner -Owner '' } | Should -Throw
    }
}

# ---------------------------------------------------------------------------
Describe 'Test-RegexPattern' {

    It 'returns true for a valid regex' {
        Test-RegexPattern -Pattern '[/\\]\.git([/\\]|$)' | Should -Be $true
    }

    It 'returns true for a simple literal pattern' {
        Test-RegexPattern -Pattern 'node_modules' | Should -Be $true
    }

    It 'returns false for an invalid regex' {
        Test-RegexPattern -Pattern '[unclosed' | Should -Be $false
    }

    It 'rejects an empty pattern due to mandatory parameter binding' {
        # PowerShell mandatory string parameter rejects empty string before function body runs
        { Test-RegexPattern -Pattern '' } | Should -Throw
    }
}

# ---------------------------------------------------------------------------
Describe 'Test-IgnoredPath' {

    It 'returns true when path matches a regex in the list' {
        $result = Test-IgnoredPath -Path 'C:\repos\project\.git\config' -RegexList @('[/\\]\.git([/\\]|$)')
        $result | Should -Be $true
    }

    It 'returns false when path does not match any regex' {
        $result = Test-IgnoredPath -Path 'C:\repos\project\src' -RegexList @('[/\\]\.git([/\\]|$)')
        $result | Should -Be $false
    }

    It 'returns false when no patterns match the path' {
        # Mandatory string[] rejects @(); use a pattern that will not match
        $result = Test-IgnoredPath -Path 'C:\repos\anything' -RegexList @('__nomatch__')
        $result | Should -Be $false
    }

    It 'skips invalid regex patterns gracefully without throwing' {
        { Test-IgnoredPath -Path 'C:\repos\project' -RegexList @('[unclosed', 'valid') } | Should -Not -Throw
    }
}

# ---------------------------------------------------------------------------
Describe 'Get-DirectoryFingerprint' {

    It 'returns a valid object for the project root' {
        $fp = Get-DirectoryFingerprint `
            -Path "$PSScriptRoot\.." `
            -IgnoreDirNames @('node_modules', '.git') `
            -IgnorePathRegex @('[/\\]\.git([/\\]|$)')

        $fp | Should -Not -BeNullOrEmpty
        $fp.SampleFileCount | Should -BeGreaterOrEqual 0
        $fp.TotalFileBytes  | Should -BeGreaterOrEqual 0
        $fp.Extensions      | Should -Not -BeNullOrEmpty
    }

    It 'returns a zero-file fingerprint for a nonexistent path without throwing' {
        # Mandatory string[] rejects @(); use a placeholder that matches nothing
        $fp = Get-DirectoryFingerprint `
            -Path "$PSScriptRoot\..\__nonexistent__" `
            -IgnoreDirNames @('__placeholder__') `
            -IgnorePathRegex @('__nomatch__')

        $fp.SampleFileCount | Should -Be 0
    }

    It 'respects MaxFiles limit' {
        $fp = Get-DirectoryFingerprint `
            -Path "$PSScriptRoot\.." `
            -IgnoreDirNames @('node_modules') `
            -IgnorePathRegex @('[/\\]\.git([/\\]|$)') `
            -MaxFiles 2

        $fp.SampleFileCount | Should -BeLessOrEqual 2
    }
}

# ---------------------------------------------------------------------------
Describe 'Get-PotentialLocalDuplicates' {

    It 'returns an empty array for an empty input collection' {
        $result = Get-PotentialLocalDuplicates -LocalItems @()
        @($result).Count | Should -Be 0
    }

    It 'returns an empty array for a single-item collection' {
        $item = [pscustomobject]@{
            GitRepoName = 'my-repo'
            FolderName  = 'my-repo'
            LocalPath   = 'C:\repos\my-repo'
            CurrentBranch   = 'main'
            LastCommitDate  = $null
            ModifiedCount   = 0
            Fingerprint = [pscustomobject]@{
                TopLevelDirs = @('src', 'docs')
                KeyFiles     = @('README.md')
                Extensions   = @('.ps1', '.md')
            }
        }
        $result = Get-PotentialLocalDuplicates -LocalItems @($item)
        @($result).Count | Should -Be 0
    }

    It 'detects two identical items as a duplicate pair' {
        $item = [pscustomobject]@{
            GitRepoName = 'shared-repo'
            FolderName  = 'shared-repo'
            LocalPath   = 'C:\repos\shared-repo'
            CurrentBranch   = 'main'
            LastCommitDate  = $null
            ModifiedCount   = 0
            Fingerprint = [pscustomobject]@{
                TopLevelDirs = @('src', 'docs', 'tests')
                KeyFiles     = @('README.md', 'package.json')
                Extensions   = @('.js', '.md', '.json')
            }
        }
        $itemB = [pscustomobject]@{
            GitRepoName = 'shared-repo'
            FolderName  = 'shared-repo'
            LocalPath   = 'C:\repos\backup\shared-repo'
            CurrentBranch   = 'main'
            LastCommitDate  = $null
            ModifiedCount   = 0
            Fingerprint = [pscustomobject]@{
                TopLevelDirs = @('src', 'docs', 'tests')
                KeyFiles     = @('README.md', 'package.json')
                Extensions   = @('.js', '.md', '.json')
            }
        }
        $result = Get-PotentialLocalDuplicates -LocalItems @($item, $itemB)
        @($result).Count | Should -BeGreaterThan 0
    }

    It 'does not flag two completely different items as duplicates' {
        $itemA = [pscustomobject]@{
            GitRepoName = 'react-app'
            FolderName  = 'react-app'
            LocalPath   = 'C:\repos\react-app'
            CurrentBranch   = 'main'
            LastCommitDate  = $null
            ModifiedCount   = 0
            Fingerprint = [pscustomobject]@{
                TopLevelDirs = @('src', 'public', 'node_modules')
                KeyFiles     = @('package.json', 'vite.config.js')
                Extensions   = @('.jsx', '.css', '.html')
            }
        }
        $itemB = [pscustomobject]@{
            GitRepoName = 'python-ml-pipeline'
            FolderName  = 'python-ml-pipeline'
            LocalPath   = 'C:\repos\python-ml-pipeline'
            CurrentBranch   = 'main'
            LastCommitDate  = $null
            ModifiedCount   = 0
            Fingerprint = [pscustomobject]@{
                TopLevelDirs = @('data', 'models', 'notebooks')
                KeyFiles     = @('requirements.txt', 'pyproject.toml')
                Extensions   = @('.py', '.ipynb', '.csv')
            }
        }
        $result = Get-PotentialLocalDuplicates -LocalItems @($itemA, $itemB)
        @($result).Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
Describe 'Compare-LocalAndGitHub' {

    BeforeAll {
        $script:SampleGhRepo = [pscustomobject]@{
            RepoName      = 'my-project'
            NameWithOwner = 'xfaith4/my-project'
            Url           = 'https://github.com/xfaith4/my-project'
            SshUrl        = 'git@github.com:xfaith4/my-project.git'
            UpdatedAt     = '2026-01-01T00:00:00Z'
            IsArchived    = $false
        }
    }

    It 'returns GitHubOnly entry when local list is empty' {
        $result = Compare-LocalAndGitHub -LocalItems @() -GitHubItems @($script:SampleGhRepo)
        @($result).Count | Should -Be 1
        $result[0].Status | Should -Be 'GitHubOnly'
    }

    It 'returns LocalOnly entry when GitHub list is empty' {
        $local = [pscustomobject]@{
            LocalRoot      = 'G:\Development'
            FolderName     = 'orphan-repo'
            LocalPath      = 'G:\Development\orphan-repo'
            IsGitRepo      = $true
            GitOriginUrl   = $null
            GitOwnerGuess  = $null
            GitRepoName    = 'orphan-repo'
            CurrentBranch  = 'main'
            LastCommitDate = $null
            ModifiedCount  = 0
            UntrackedCount = 0
        }
        $result = Compare-LocalAndGitHub -LocalItems @($local) -GitHubItems @()
        @($result).Count | Should -Be 1
        $result[0].Status | Should -Be 'LocalOnly'
    }

    It 'returns an empty array when both inputs are empty' {
        $result = Compare-LocalAndGitHub -LocalItems @() -GitHubItems @()
        @($result).Count | Should -Be 0
    }

    It 'matches a local repo to GitHub by repo name' {
        $local = [pscustomobject]@{
            LocalRoot      = 'G:\Development'
            FolderName     = 'my-project'
            LocalPath      = 'G:\Development\my-project'
            IsGitRepo      = $true
            GitOriginUrl   = $null
            GitOwnerGuess  = $null
            GitRepoName    = 'my-project'
            CurrentBranch  = 'main'
            LastCommitDate = $null
            ModifiedCount  = 0
            UntrackedCount = 0
        }
        $result = Compare-LocalAndGitHub -LocalItems @($local) -GitHubItems @($script:SampleGhRepo)
        $matched = @($result | Where-Object { $_.Status -eq 'Matched' })
        $matched.Count | Should -Be 1
        $matched[0].GitHubRepo | Should -Be 'xfaith4/my-project'
    }

    It 'matches a local repo to GitHub by origin URL' {
        $local = [pscustomobject]@{
            LocalRoot      = 'G:\Development'
            FolderName     = 'cloned-project'
            LocalPath      = 'G:\Development\cloned-project'
            IsGitRepo      = $true
            GitOriginUrl   = 'https://github.com/xfaith4/my-project'
            GitOwnerGuess  = 'xfaith4'
            GitRepoName    = 'my-project'
            CurrentBranch  = 'main'
            LastCommitDate = $null
            ModifiedCount  = 0
            UntrackedCount = 0
        }
        $result = Compare-LocalAndGitHub -LocalItems @($local) -GitHubItems @($script:SampleGhRepo)
        $matched = @($result | Where-Object { $_.Status -eq 'Matched' })
        $matched.Count | Should -Be 1
        $matched[0].MatchReason | Should -Be 'OriginUrl'
    }
}

# ---------------------------------------------------------------------------
Describe 'Get-SimilarityScore' {

    It 'returns a high score for two identical repo names and folder names' {
        $a = [pscustomobject]@{
            GitRepoName = 'duplicate-repo'
            FolderName  = 'duplicate-repo'
            Fingerprint = [pscustomobject]@{
                TopLevelDirs = @('src')
                KeyFiles     = @('README.md')
                Extensions   = @('.ps1')
            }
        }
        $b = [pscustomobject]@{
            GitRepoName = 'duplicate-repo'
            FolderName  = 'duplicate-repo'
            Fingerprint = [pscustomobject]@{
                TopLevelDirs = @('src')
                KeyFiles     = @('README.md')
                Extensions   = @('.ps1')
            }
        }
        $score = Get-SimilarityScore -LocalA $a -LocalB $b
        $score | Should -BeGreaterOrEqual 50
    }

    It 'returns a low score for two completely unrelated items' {
        $a = [pscustomobject]@{
            GitRepoName = 'web-frontend'
            FolderName  = 'web-frontend'
            Fingerprint = [pscustomobject]@{
                TopLevelDirs = @('public', 'components')
                KeyFiles     = @('vite.config.js')
                Extensions   = @('.jsx', '.css')
            }
        }
        $b = [pscustomobject]@{
            GitRepoName = 'data-pipeline'
            FolderName  = 'data-pipeline'
            Fingerprint = [pscustomobject]@{
                TopLevelDirs = @('notebooks', 'data')
                KeyFiles     = @('requirements.txt')
                Extensions   = @('.py', '.csv')
            }
        }
        $score = Get-SimilarityScore -LocalA $a -LocalB $b
        $score | Should -BeLessThan 50
    }
}

# ---------------------------------------------------------------------------
Describe 'ConvertTo-HtmlTable' {

    It 'generates a table element for empty data' {
        $html = ConvertTo-HtmlTable -Data @() -Columns @('Name', 'Path')
        $html | Should -Match '<table>'
        $html | Should -Match '</table>'
    }

    It 'includes column headers in the output' {
        $html = ConvertTo-HtmlTable -Data @() -Columns @('FolderName', 'LocalPath')
        $html | Should -Match 'FolderName'
        $html | Should -Match 'LocalPath'
    }

    It 'renders a data row for a single item' {
        $data = @([pscustomobject]@{ FolderName = 'my-repo'; LocalPath = 'C:\repos\my-repo' })
        $html = ConvertTo-HtmlTable -Data $data -Columns @('FolderName', 'LocalPath')
        $html | Should -Match 'my-repo'
        # Escape backslashes for regex matching
        $html | Should -Match 'C:\\repos\\my-repo'
    }

    It 'HTML-encodes values with special characters' {
        $data = @([pscustomobject]@{ FolderName = '<script>alert(1)</script>'; LocalPath = '' })
        $html = ConvertTo-HtmlTable -Data $data -Columns @('FolderName', 'LocalPath')
        $html | Should -Not -Match '<script>'
        $html | Should -Match '&lt;script&gt;'
    }
}

# ---------------------------------------------------------------------------
Describe 'Get-SimilarityScore - Phase 3 scoring rules' {

    BeforeAll {
        $script:StructuredFingerprint = [pscustomobject]@{
            TopLevelDirs = @('src', 'docs', 'tests')
            KeyFiles     = @('README.md', 'package.json')
            Extensions   = @('.js', '.md', '.json')
        }
    }

    It 'returns 0 when both repos have different known remote origins' {
        $a = [pscustomobject]@{
            GitOriginUrl = 'https://github.com/xfaith4/repo-alpha'
            GitRepoName  = 'repo-alpha'
            FolderName   = 'repo-alpha'
            Fingerprint  = $script:StructuredFingerprint
        }
        $b = [pscustomobject]@{
            GitOriginUrl = 'https://github.com/xfaith4/repo-beta'
            GitRepoName  = 'repo-beta'
            FolderName   = 'repo-beta'
            Fingerprint  = $script:StructuredFingerprint
        }
        Get-SimilarityScore -LocalA $a -LocalB $b | Should -Be 0
    }

    It 'scores normally when one repo has no origin URL' {
        $a = [pscustomobject]@{
            GitOriginUrl = $null
            GitRepoName  = 'shared-name'
            FolderName   = 'shared-name'
            Fingerprint  = $script:StructuredFingerprint
        }
        $b = [pscustomobject]@{
            GitOriginUrl = 'https://github.com/xfaith4/shared-name'
            GitRepoName  = 'shared-name'
            FolderName   = 'shared-name'
            Fingerprint  = $script:StructuredFingerprint
        }
        $score = Get-SimilarityScore -LocalA $a -LocalB $b
        $score | Should -BeGreaterThan 0
    }

    It 'scores normally when both repos have the same origin URL' {
        $a = [pscustomobject]@{
            GitOriginUrl = 'https://github.com/xfaith4/my-project'
            GitRepoName  = 'my-project'
            FolderName   = 'my-project'
            Fingerprint  = $script:StructuredFingerprint
        }
        $b = [pscustomobject]@{
            GitOriginUrl = 'https://github.com/xfaith4/my-project'
            GitRepoName  = 'my-project'
            FolderName   = 'my-project'
            Fingerprint  = $script:StructuredFingerprint
        }
        $score = Get-SimilarityScore -LocalA $a -LocalB $b
        $score | Should -BeGreaterOrEqual 65
    }

    It 'score of 50 alone (name match only) no longer reaches threshold of 65' {
        # A name-only match scores 50, which is below the new threshold of 65
        $a = [pscustomobject]@{
            GitOriginUrl = $null
            GitRepoName  = 'common-name'
            FolderName   = 'different-folder-a'
            Fingerprint  = [pscustomobject]@{
                TopLevelDirs = @('alpha')
                KeyFiles     = @()
                Extensions   = @('.go')
            }
        }
        $b = [pscustomobject]@{
            GitOriginUrl = $null
            GitRepoName  = 'common-name'
            FolderName   = 'different-folder-b'
            Fingerprint  = [pscustomobject]@{
                TopLevelDirs = @('beta')
                KeyFiles     = @()
                Extensions   = @('.py')
            }
        }
        $score = Get-SimilarityScore -LocalA $a -LocalB $b
        $score | Should -BeLessThan 65
    }
}

# ---------------------------------------------------------------------------
Describe 'Get-PotentialLocalDuplicates - Phase 3 classification' {

    BeforeAll {
        $script:SharedFingerprint = [pscustomobject]@{
            TopLevelDirs = @('src', 'docs', 'tests', 'config')
            KeyFiles     = @('README.md', 'package.json', 'tsconfig.json')
            Extensions   = @('.ts', '.md', '.json', '.yml')
        }
    }

    It 'classifies same-origin duplicates as SameOrigin with High confidence' {
        $a = [pscustomobject]@{
            GitOriginUrl   = 'https://github.com/xfaith4/my-app'
            GitRepoName    = 'my-app'
            FolderName     = 'my-app'
            LocalPath      = 'G:\Development\my-app'
            CurrentBranch  = 'main'
            LastCommitDate = $null
            ModifiedCount  = 0
            Fingerprint    = $script:SharedFingerprint
        }
        $b = [pscustomobject]@{
            GitOriginUrl   = 'https://github.com/xfaith4/my-app'
            GitRepoName    = 'my-app'
            FolderName     = 'my-app-backup'
            LocalPath      = 'G:\Backup\my-app'
            CurrentBranch  = 'main'
            LastCommitDate = $null
            ModifiedCount  = 0
            Fingerprint    = $script:SharedFingerprint
        }
        $result = Get-PotentialLocalDuplicates -LocalItems @($a, $b)
        @($result).Count | Should -BeGreaterThan 0
        $result[0].DuplicateType | Should -Be 'SameOrigin'
        $result[0].Confidence    | Should -Be 'High'
    }

    It 'classifies same-name duplicates as SameName with Medium confidence' {
        $a = [pscustomobject]@{
            GitOriginUrl   = $null
            GitRepoName    = 'my-project'
            FolderName     = 'my-project'
            LocalPath      = 'G:\Development\my-project'
            CurrentBranch  = 'main'
            LastCommitDate = $null
            ModifiedCount  = 0
            Fingerprint    = $script:SharedFingerprint
        }
        $b = [pscustomobject]@{
            GitOriginUrl   = $null
            GitRepoName    = 'my-project'
            FolderName     = 'my-project'
            LocalPath      = 'G:\Archive\my-project'
            CurrentBranch  = 'main'
            LastCommitDate = $null
            ModifiedCount  = 0
            Fingerprint    = $script:SharedFingerprint
        }
        $result = Get-PotentialLocalDuplicates -LocalItems @($a, $b)
        @($result).Count | Should -BeGreaterThan 0
        $result[0].DuplicateType | Should -Be 'SameName'
        $result[0].Confidence    | Should -Be 'Medium'
    }

    It 'result records contain OriginA and OriginB fields' {
        $a = [pscustomobject]@{
            GitOriginUrl   = 'https://github.com/xfaith4/shared-app'
            GitRepoName    = 'shared-app'
            FolderName     = 'shared-app'
            LocalPath      = 'G:\Development\shared-app'
            CurrentBranch  = 'main'
            LastCommitDate = $null
            ModifiedCount  = 0
            Fingerprint    = $script:SharedFingerprint
        }
        $b = [pscustomobject]@{
            GitOriginUrl   = 'https://github.com/xfaith4/shared-app'
            GitRepoName    = 'shared-app'
            FolderName     = 'shared-app-copy'
            LocalPath      = 'G:\Backup\shared-app'
            CurrentBranch  = 'main'
            LastCommitDate = $null
            ModifiedCount  = 0
            Fingerprint    = $script:SharedFingerprint
        }
        $result = Get-PotentialLocalDuplicates -LocalItems @($a, $b)
        @($result).Count | Should -BeGreaterThan 0
        $result[0].PSObject.Properties.Name | Should -Contain 'OriginA'
        $result[0].PSObject.Properties.Name | Should -Contain 'OriginB'
    }

    It 'does not flag repos with different origins as duplicates' {
        $a = [pscustomobject]@{
            GitOriginUrl   = 'https://github.com/xfaith4/project-a'
            GitRepoName    = 'project-a'
            FolderName     = 'project-a'
            LocalPath      = 'G:\Development\project-a'
            CurrentBranch  = 'main'
            LastCommitDate = $null
            ModifiedCount  = 0
            Fingerprint    = $script:SharedFingerprint
        }
        $b = [pscustomobject]@{
            GitOriginUrl   = 'https://github.com/xfaith4/project-b'
            GitRepoName    = 'project-a'
            FolderName     = 'project-a'
            LocalPath      = 'G:\Development\work\project-a'
            CurrentBranch  = 'main'
            LastCommitDate = $null
            ModifiedCount  = 0
            Fingerprint    = $script:SharedFingerprint
        }
        $result = Get-PotentialLocalDuplicates -LocalItems @($a, $b)
        @($result).Count | Should -Be 0
    }
}
