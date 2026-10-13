# MusicLibrary_v2 roadmap execution pilot

Owner authorization: D-025, 2026-10-13. Goal: finish the existing MusicLibrary_v2
roadmap with product acceptance evidence and use it to prove Repository Manager
can advance implementation rather than only improve repository documentation.

## Scope and ordering

- Target repository: xfaith4/MusicLibrary_v2, target branch main.
- Roadmap: F:/Development/20_Staging/MusicLibraryProjects/MusicLibrary_v2/ROADMAP.md.
- Isolated branch: feat/roadmap-finalization.
- Preserve original checkout and its line-ending changes (no content differences
  from HEAD found during initial audit).
- Phase 28 is the roadmap's last v2.0 release blocker. Finish and prove packaging
  first. Phase 26 and post-launch Phase 27 remain in the full-roadmap objective;
  do not erase them to manufacture completion. Deferred items remain distinct.
- Source checks cannot prove clean-Windows installation or real browser audio.
  Those acceptance gates stay open until executed and recorded.

## Promotion

Standing owner approval permits automatic ordinary engineering promotion. A
runtime authorization must bind the actual plan fingerprint and work-unit IDs,
limits, scope, network allowlist and cancellation state before orchestration.
This document is a project record, not a simulated active runtime mandate.
The pure gate is Test-GuardedPromotion in Execution.PromotionPolicy.ps1. It must
be wired to trusted verification/review/protection inputs before automatic merge.
GitHub checks and review must name the exact head. Reserved-class changes need
owner review. No force push or branch-protection bypass. Verify merge reachability
and reconcile before dependent work advances.

## Acceptance

1. Run the existing backend and frontend suites against synthetic data.
2. Build and inspect a versioned Windows artifact with bundled dependencies.
3. On a clean Windows machine: install, choose a sample library, scan and play.
4. Prove update checking is opt-in and uninstall preserves music and user data.
5. Complete remaining Phase 26/27 work with focused tests and runtime acceptance.
6. Prove runner restart, no duplicate claims, cancellation and dependent continuation.
7. Only then report finalized product or integrated phase completion.

## Worktree prerequisite discovered

The canonical module smoke was red on a linked worktree: documentation discovery
looked only for .git directories and returned zero repositories for a .git file.
The bounded correction recognizes both marker forms. This is required for
isolated runner workspaces, not a new documentation-quality initiative.

## 2026-10-13 evidence boundary

GitHub allow_auto_merge was enabled on both repositories under the owner's
explicit approval; no branch-protection settings changed and no PR merged.
Manager main requires smoke and enforces administrators. Pilot main currently
has no branch protection; a runner must still enforce its explicit checks.
The pilot has one unpublished existing Phase 25 commit (81523a9), retained.
The manager's remote main has the same source tree as the starting checkout.

Module smoke passed after linked-worktree discovery was corrected and the
generated contract mirror synchronized. The full local suite did not pass:
its first module run preceded those corrections, frontend dependencies were
absent in the isolated checkout, and the analyzer sweep stalled; stopped after
approximately fifteen minutes. Exact-head CI and independent review remain open.
More than two manager PRs were already open; do not open a third review PR.

Pilot local proof: 399 backend tests, 228 frontend tests, production frontend
build and the PowerShell scanner/persistence/backup suite passed. A Windows
packaged smoke passed bundled API startup, generated-WAV inventory/ffprobe
metadata, range-byte streaming, upgrade and uninstall preservation. This is
not clean-VM or audible browser proof. Phase 26/27 and runner continuation
remain open; the product is not finalized.
