@{
    # PSScriptAnalyzer policy for this repo (ROADMAP Lane 0.8), consumed by
    # scripts/Invoke-LintGate.ps1 (the suite/CI gate) and picked up
    # automatically by the VS Code PowerShell extension.
    #
    # Exclusions are POLICY (deliberate architecture), not debt. Debt is
    # handled by the per-rule ratchet baseline in scripts/pssa-baseline.json,
    # which may only shrink.
    ExcludeRules = @(
        # Gate scripts and operator tooling use Write-Host as their UI on
        # purpose: colored PASS/FAIL output for a human at a console. The
        # repo's linters additionally EMIT findings on the information stream
        # and tests capture it with *>&1 — replacing Write-Host would break
        # that contract, not improve it. 723 findings at adoption.
        'PSAvoidUsingWriteHost'
    )
}
