# roadmap-audit-action

A composite GitHub Action (Release 2.3 Phase 3) that audits a `ROADMAP.md`
against the Roadmap Contract Standard and **fails the check run** on structural
errors — so a PR that breaks the roadmap contract is caught in CI.

## Usage

```yaml
- uses: ./.github/actions/roadmap-audit-action
  with:
    roadmap-path: ROADMAP.md   # optional (default: ROADMAP.md)
    fail-on-error: "true"      # optional (default: "true")
```

## Behavior

- If the source repo's richer validator (`tools/Test-RoadmapStructure.ps1`) is
  present, it is used (full release-order / duplicate-heading / size checks).
- Otherwise `audit.ps1` runs dependency-free baseline checks: file exists and is
  non-empty, at least one release heading, at least one checkbox item, and no
  duplicate headings.
- Errors are emitted as `::error::` annotations; with `fail-on-error: true` the
  step exits non-zero, failing the check run.

## Local test

The `roadmap-audit-action package` gate in `scripts/Invoke-TestSuite.ps1`
(`npm test`) runs `audit.ps1` against this repo's `ROADMAP.md` and asserts it
passes, and that `action.yml` is a valid composite action.

> Running in a GitHub-hosted runner and posting the check run is verified by CI,
> not by the local suite.
