# D-025: pure promotion decision. Evidence must come from the verification,
# review and orchestration services, never an implementation agent's result.
Set-StrictMode -Version Latest

function Test-GuardedPromotion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Authorization,
        [Parameter(Mandatory)][object]$Evidence,
        [Parameter(Mandatory)][datetimeoffset]$Now
    )
    $reasons = New-Object 'System.Collections.Generic.List[string]'
    function Read-PromotionField($Object, [string]$Name, $Default = $null) {
        if ($null -eq $Object) { return $Default }
        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($Name)) { return $Object[$Name] }
        } elseif ($null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
        return $Default
    }
    $auth = $Authorization; $ev = $Evidence
    if ((Read-PromotionField $auth 'schemaVersion') -ne 'v1') { $reasons.Add('authorization-schema') }
    if ((Read-PromotionField $auth 'state') -ne 'active') { $reasons.Add('authorization-inactive') }
    if ((Read-PromotionField $auth 'posture') -ne 'guarded' -or (Read-PromotionField $auth 'automaticMerge') -isnot [bool] -or (Read-PromotionField $auth 'automaticMerge') -ne $true) { $reasons.Add('automatic-merge-not-authorized') }
    if ([string]::IsNullOrWhiteSpace([string](Read-PromotionField $auth 'id'))) { $reasons.Add('authorization-id-missing') }
    if ([string]::IsNullOrWhiteSpace([string](Read-PromotionField $auth 'ownerApprovalRef'))) { $reasons.Add('owner-approval-missing') }
    $expiry = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string](Read-PromotionField $auth 'expiresAt'), [ref]$expiry) -or $Now -ge $expiry) { $reasons.Add('authorization-expired') }
    foreach ($key in @('repository','targetBranch','planFingerprint','workUnitId')) {
        $expected = [string](Read-PromotionField $auth $key)
        if ([string]::IsNullOrWhiteSpace($expected) -or $expected -cne [string](Read-PromotionField $ev $key)) { $reasons.Add("mismatch-$key") }
    }
    $head = [string](Read-PromotionField $ev 'headSha')
    if ($head -notmatch '^[a-f0-9]{40}$') { $reasons.Add('head-invalid') }
    foreach ($key in @('verificationHeadSha','reviewHeadSha')) {
        if ($head -cne [string](Read-PromotionField $ev $key)) { $reasons.Add("stale-$key") }
    }
    foreach ($key in @('scopePassed','permissionEnvelopePassed','budgetsPassed','branchProtectionPassed','independentReviewPassed','workspaceSafe','prReady')) {
        if ((Read-PromotionField $ev $key) -isnot [bool] -or (Read-PromotionField $ev $key) -ne $true) { $reasons.Add("missing-or-failed-$key") }
    }
    if ((Read-PromotionField $ev 'cancellationChecked') -isnot [bool] -or (Read-PromotionField $ev 'cancellationChecked') -ne $true -or (Read-PromotionField $ev 'cancelled') -isnot [bool] -or (Read-PromotionField $ev 'cancelled') -ne $false) { $reasons.Add('cancellation-not-clear') }
    $implementer = [string](Read-PromotionField $ev 'implementerId')
    $reviewer = [string](Read-PromotionField $ev 'reviewerId')
    if ([string]::IsNullOrWhiteSpace($implementer) -or [string]::IsNullOrWhiteSpace($reviewer) -or $implementer -eq $reviewer) { $reasons.Add('review-not-independent') }
    $required = @(Read-PromotionField $ev 'requiredChecks' @())
    $checks = @(Read-PromotionField $ev 'checks' @())
    if ($required.Count -eq 0 -or $checks.Count -eq 0) { $reasons.Add('checks-empty') }
    foreach ($name in $required) {
        $matches = @($checks | Where-Object { (Read-PromotionField $_ 'name') -ceq $name })
        if ([string]::IsNullOrWhiteSpace([string]$name) -or $matches.Count -ne 1) { $reasons.Add("check-missing-or-ambiguous:$name"); continue }
        $check = $matches[0]
        if ((Read-PromotionField $check 'headSha') -cne $head -or (Read-PromotionField $check 'status') -ne 'completed' -or (Read-PromotionField $check 'conclusion') -ne 'success') { $reasons.Add("check-not-passed:$name") }
    }
    $paths = @(Read-PromotionField $ev 'changedPaths' @())
    $allowed = @(Read-PromotionField $auth 'scopePaths' @())
    $forbidden = @('.github/workflows/*') + @(Read-PromotionField $auth 'forbiddenPaths' @())
    if ($paths.Count -eq 0 -or $allowed.Count -eq 0) { $reasons.Add('scope-empty') }
    foreach ($rawPath in $paths) {
        $path = ([string]$rawPath).Replace('\','/')
        if ($path -match '(^/|(^|/)\.\.(/|$)|^[A-Za-z]:)' -or [string]::IsNullOrWhiteSpace($path)) { $reasons.Add("invalid-path:$path"); continue }
        if (@($allowed | Where-Object { $path -like $_ }).Count -eq 0) { $reasons.Add("out-of-scope:$path") }
        if (@($forbidden | Where-Object { $path -like $_ }).Count -gt 0) { $reasons.Add("forbidden-path:$path") }
    }
    # The scope service classifies reserved changes (including semantic changes
    # to verdicts/production/data that filenames alone cannot establish).
    if ((Read-PromotionField $ev 'reservedClassesChecked') -isnot [bool] -or (Read-PromotionField $ev 'reservedClassesChecked') -ne $true) { $reasons.Add('reserved-classes-unchecked') }
    $reserved = @(Read-PromotionField $ev 'reservedClasses' @())
    if ($reserved.Count -gt 0 -and (Read-PromotionField $ev 'ownerReviewedHeadSha') -cne $head) { $reasons.Add('reserved-owner-review-required') }
    [pscustomobject]@{ allowed = ($reasons.Count -eq 0); reasons = @($reasons); headSha = $head; authorizationId = Read-PromotionField $auth 'id' }
}
