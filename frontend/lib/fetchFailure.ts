/**
 * Classify a dashboard load failure into something an operator can act on.
 *
 * The screen this replaces rendered the raw exception string and nothing else:
 * `Failed to fetch`, centred, on an otherwise empty page — no retry, no
 * explanation, and no way to tell "the backend is not running" apart from "this
 * portal has no repositories configured yet". Those two need opposite actions,
 * and a terminal screen that names neither leaves the operator guessing.
 *
 * Pure and string-based on purpose: the browser gives us a `TypeError` message
 * for a dead connection, not a status code, so the message is the only signal
 * available at this layer.
 */

export type FetchFailureKind =
  | 'backend-unreachable'
  | 'auth-required'
  | 'not-configured'
  | 'backend-error';

export interface FetchFailureState {
  kind: FetchFailureKind;
  /** Short statement of what is wrong. */
  headline: string;
  /** What the operator should do about it. Always present — this is the point. */
  nextStep: string;
  /** The underlying message, kept verbatim so nothing is hidden. */
  detail: string | null;
  /** Label for the retry control; null when retrying cannot help. */
  retryLabel: string | null;
}

const UNREACHABLE = /failed to fetch|networkerror|network error|load failed|err_connection|econnrefused|fetch failed/i;
const AUTH = /\b401\b|\b403\b|unauthori[sz]ed|forbidden|not authenticated|login required/i;
const NOT_CONFIGURED = /no repositories|no local roots|not configured|inventory is empty|run setup/i;

/**
 * @param error   The error string the dashboard is holding, if any.
 * @param options `hasRepos` distinguishes a total load failure from a partial one.
 */
export function classifyFetchFailure(
  error: string | null | undefined,
  options: { hasRepos: boolean } = { hasRepos: false },
): FetchFailureState | null {
  if (!error || !String(error).trim()) return null;
  // A failure with repositories already on screen is not a terminal state — the
  // dashboard still renders, and the error belongs inline rather than here.
  if (options.hasRepos) return null;

  const detail = String(error).trim();

  if (UNREACHABLE.test(detail)) {
    return {
      kind: 'backend-unreachable',
      headline: 'The portal cannot reach its backend.',
      nextStep: 'Start the API host (Start-App.ps1), then retry. If it is already running, check that the portal is pointed at the right port.',
      detail,
      retryLabel: 'Retry connection',
    };
  }

  if (AUTH.test(detail)) {
    return {
      kind: 'auth-required',
      headline: 'The backend refused this request.',
      nextStep: 'Sign in again. If portal login is enforced, your session may have expired.',
      detail,
      retryLabel: 'Retry',
    };
  }

  if (NOT_CONFIGURED.test(detail)) {
    return {
      kind: 'not-configured',
      headline: 'No repositories are configured yet.',
      nextStep: 'Add at least one local root in Settings, then run a scan. Nothing is wrong with the backend.',
      detail,
      retryLabel: 'Scan again',
    };
  }

  return {
    kind: 'backend-error',
    headline: 'The backend answered with an error.',
    nextStep: 'Retry once; if it repeats, check the API host log for the matching correlation id.',
    detail,
    retryLabel: 'Retry',
  };
}
