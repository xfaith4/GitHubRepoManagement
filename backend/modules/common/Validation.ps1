function Test-ReconciliationArtifactShape {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$LocalItems,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$GitHubItems,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Comparison,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$PotentialDuplicates
    )

    $requiredComparisonFields = @('Status', 'MatchReason')
    foreach ($item in @($Comparison)) {
        foreach ($field in $requiredComparisonFields) {
            if (-not $item.PSObject.Properties.Name.Contains($field)) {
                return [pscustomobject]@{
                    IsValid = $false
                    Reason = "Comparison item missing required field '$field'."
                }
            }
        }
    }

    foreach ($dup in @($PotentialDuplicates)) {
        if (-not $dup.PSObject.Properties.Name.Contains('DuplicateType')) {
            return [pscustomobject]@{
                IsValid = $false
                Reason = "Duplicate item missing required field 'DuplicateType'."
            }
        }
    }

    return [pscustomobject]@{
        IsValid = $true
        Reason = ''
    }
}
