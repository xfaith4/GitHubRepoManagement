/**
 * The portal saying which code you are actually looking at.
 *
 * There are two halves and they move independently. `frontend/dist` is served
 * per-request, so `npm run build` puts a new UI in front of you with no
 * restart. The API host only changes when the Windows service is restarted,
 * which needs elevation. So "is this the updated portal?" has two answers, and
 * a single version number would confidently give the wrong one — a fresh
 * bundle served by a host still running last week's code looks identical to a
 * fully updated portal.
 *
 * Hence: report both, and say plainly when they disagree.
 */

export interface PortalVersionPayload {
  commit?: string | null;
  branch?: string | null;
  startedAtUtc?: string | null;
}

export type BuildStampState =
  /** UI and API came from the same commit. */
  | 'matched'
  /** Both known, and different — the host is running other code. */
  | 'mismatched'
  /** The API did not answer, or reported no commit. */
  | 'api-unknown'
  /** The bundle was built outside a git checkout. */
  | 'ui-unknown';

export interface BuildStampView {
  state: BuildStampState;
  /** Short text for the header chip. */
  label: string;
  /** Full explanation for the chip's title/tooltip. */
  detail: string;
  /** True only when the two halves are known to differ. */
  drifted: boolean;
}

function formatTime(iso: string | null | undefined): string {
  if (!iso) return 'unknown';
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return 'unknown';
  return parsed.toLocaleString();
}

/**
 * Builds the header chip's view from the two stamps.
 *
 * `uiCommit` null means the bundle was built outside a checkout; that is
 * reported as unknown rather than smoothed over, because a fabricated version
 * would defeat the only purpose this chip has.
 */
export function resolveBuildStamp(
  uiCommit: string | null,
  uiBuiltAt: string,
  api: PortalVersionPayload | null,
): BuildStampView {
  const apiCommit = api?.commit ?? null;
  const uiBuiltLabel = formatTime(uiBuiltAt);
  const apiStartedLabel = formatTime(api?.startedAtUtc);
  const branch = api?.branch ? ` (${api.branch})` : '';

  if (!uiCommit) {
    return {
      state: 'ui-unknown',
      label: `built ${uiBuiltLabel}`,
      detail:
        `This bundle was built outside a git checkout, so it cannot name its commit. ` +
        `Built ${uiBuiltLabel}. API host: ${apiCommit ?? 'unknown'}${branch}, started ${apiStartedLabel}.`,
      drifted: false,
    };
  }

  if (!apiCommit) {
    return {
      state: 'api-unknown',
      label: uiCommit,
      detail:
        `UI ${uiCommit}, built ${uiBuiltLabel}. ` +
        `The API host did not report a version, so whether it is running this same commit is unknown.`,
      drifted: false,
    };
  }

  if (apiCommit === uiCommit) {
    return {
      state: 'matched',
      label: uiCommit,
      detail:
        `UI and API host both at ${uiCommit}${branch}. ` +
        `UI built ${uiBuiltLabel}; host started ${apiStartedLabel}.`,
      drifted: false,
    };
  }

  return {
    state: 'mismatched',
    label: `ui ${uiCommit} · api ${apiCommit}`,
    detail:
      `The page is ${uiCommit} but the API host is running ${apiCommit}${branch}. ` +
      `frontend/dist goes live on rebuild; the host only picks up backend changes when the ` +
      `RepoMgmtPortal service is restarted (needs elevation). Host started ${apiStartedLabel}.`,
    drifted: true,
  };
}
