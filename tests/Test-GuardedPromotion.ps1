[CmdletBinding()]
param([switch]$FailOnError)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../backend/modules/execution/Execution.PromotionPolicy.ps1')
$now = [datetimeoffset]'2026-10-13T12:00:00Z'
$sha = 'a' * 40
$auth = @{ schemaVersion='v1'; id='fixture'; state='active'; posture='guarded'; automaticMerge=$true; ownerApprovalRef='fixture-owner'; expiresAt='2026-10-14T12:00:00Z'; repository='fixture/repo'; targetBranch='main'; planFingerprint='plan'; workUnitId='unit'; scopePaths=@('backend/*'); forbiddenPaths=@() }
$ev = @{ repository='fixture/repo'; targetBranch='main'; planFingerprint='plan'; workUnitId='unit'; headSha=$sha; verificationHeadSha=$sha; reviewHeadSha=$sha; scopePassed=$true; permissionEnvelopePassed=$true; budgetsPassed=$true; branchProtectionPassed=$true; independentReviewPassed=$true; workspaceSafe=$true; prReady=$true; cancellationChecked=$true; cancelled=$false; implementerId='implementer'; reviewerId='reviewer'; requiredChecks=@('tests'); checks=@(@{name='tests'; headSha=$sha; status='completed'; conclusion='success'}); changedPaths=@('backend/app.py'); reservedClassesChecked=$true; reservedClasses=@() }
function Assert-Allowed($a, $e, [bool]$Expected, [string]$Label) {
    $result = Test-GuardedPromotion -Authorization $a -Evidence $e -Now $now
    if ($result.allowed -ne $Expected) { throw "$Label expected $Expected; reasons: $($result.reasons -join ', ')" }
}
Assert-Allowed $auth $ev $true 'authorized engineering'
foreach ($field in @('scopePassed','permissionEnvelopePassed','budgetsPassed','branchProtectionPassed','independentReviewPassed','workspaceSafe','prReady','cancellationChecked','reservedClassesChecked')) {
    $bad=$ev.Clone(); $bad.Remove($field); Assert-Allowed $auth $bad $false "missing $field"
}
foreach ($field in @('verificationHeadSha','reviewHeadSha')) {
    $bad=$ev.Clone(); $bad[$field]='b'*40; Assert-Allowed $auth $bad $false "stale $field"
}
foreach ($outcome in @('skipped','neutral','failure','cancelled')) {
    $bad=$ev.Clone(); $bad.checks=@(@{name='tests'; headSha=$sha; status='completed'; conclusion=$outcome}); Assert-Allowed $auth $bad $false $outcome
}
$bad=$ev.Clone(); $bad.changedPaths=@('.github/workflows/test.yml'); Assert-Allowed $auth $bad $false 'forbidden workflow'
$bad=$ev.Clone(); $bad.cancelled=$true; Assert-Allowed $auth $bad $false 'cancelled'
$bad=$ev.Clone(); $bad.reviewerId='implementer'; Assert-Allowed $auth $bad $false 'self review'
$bad=$ev.Clone(); $bad.reservedClasses=@('governance'); Assert-Allowed $auth $bad $false 'reserved change'
$bad.ownerReviewedHeadSha=$sha; Assert-Allowed $auth $bad $true 'reserved exact-head review'
foreach ($field in @('repository','targetBranch','planFingerprint','workUnitId')) {
    $bad=$ev.Clone(); $bad[$field]='wrong'; Assert-Allowed $auth $bad $false "mismatch $field"
}
$bad=$auth.Clone(); $bad.expiresAt='2026-10-12T12:00:00Z'; Assert-Allowed $bad $ev $false 'expired'
$bad=$ev.Clone(); $bad.requiredChecks=@(); $bad.checks=@(); Assert-Allowed $auth $bad $false 'zero checks'
$bad=$ev.Clone(); $bad.budgetsPassed='true'; Assert-Allowed $auth $bad $false 'string boolean rejected'
$bad=$auth.Clone(); $bad.automaticMerge='true'; Assert-Allowed $bad $ev $false 'authorization string boolean rejected'
Write-Host 'PASS: authorized promotion and refusal fixtures; pure, no operational roots touched.'
