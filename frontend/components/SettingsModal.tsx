
import React, { useState, useEffect, useCallback } from 'react';
import { type AppSettings, type GitHubAuthStatus } from '../types';
import { saveSettings, getGitHubAuthStatus } from '../services/apiClient';

interface SettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (settings: AppSettings) => void;
  currentSettings: AppSettings;
  /**
   * Connects the GitHub API view for the given user/org. Folded in from the
   * former standalone "GitHub API" header dialog so every connection setting
   * lives in one place instead of being split across two modals.
   */
  onConnectGitHub?: (username: string) => Promise<void>;
  /** Username the GitHub view is currently connected as, when connected. */
  connectedGitHubUser?: string | null;
}

const ENV_VAR_NAME_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*$/;
const TOKEN_LOOKALIKE_PATTERN = /^(gh[pousr]_|github_pat_)/;

const SettingsModal: React.FC<SettingsModalProps> = ({ isOpen, onClose, onSave, currentSettings, onConnectGitHub, connectedGitHubUser }) => {
  const [settings, setSettings] = useState<AppSettings>(currentSettings);
  const [isSaving, setIsSaving] = useState(false);
  const [authStatus, setAuthStatus] = useState<GitHubAuthStatus | null>(null);
  const [isChecking, setIsChecking] = useState(false);
  // The save used to fail silently (console.error only), which meant a rejected
  // workspace path looked like a successful save. Surface it in the dialog.
  const [saveError, setSaveError] = useState<string | null>(null);
  const [isConnecting, setIsConnecting] = useState(false);
  const [connectError, setConnectError] = useState<string | null>(null);
  const [connectNotice, setConnectNotice] = useState<string | null>(null);

  useEffect(() => {
    setSettings(currentSettings);
  }, [currentSettings]);

  // Clear transient feedback each time the dialog opens so a stale error from a
  // previous visit is never presented as the current state.
  useEffect(() => {
    if (isOpen) {
      setSaveError(null);
      setConnectError(null);
      setConnectNotice(null);
    }
  }, [isOpen]);

  // Resolve against the host's own environment as soon as the dialog opens, so
  // an unreadable variable name is visible before the operator saves it.
  const refreshAuthStatus = useCallback(async (validate: boolean) => {
    setIsChecking(true);
    try {
      setAuthStatus(await getGitHubAuthStatus(validate));
    } catch (error) {
      console.error('Failed to read GitHub auth status', error);
      setAuthStatus(null);
    } finally {
      setIsChecking(false);
    }
  }, []);

  useEffect(() => {
    if (isOpen) void refreshAuthStatus(false);
  }, [isOpen, refreshAuthStatus]);

  if (!isOpen) return null;

  const envVarName = settings.gitHubTokenEnvVar ?? '';
  const envVarNameChanged = envVarName !== (currentSettings.gitHubTokenEnvVar ?? '');
  const envVarNameError =
    envVarName && TOKEN_LOOKALIKE_PATTERN.test(envVarName)
      ? 'That looks like a token, not a variable name. Enter the NAME of the variable that holds it.'
      : envVarName && !ENV_VAR_NAME_PATTERN.test(envVarName)
        ? 'Use letters, digits, and underscores, starting with a letter or underscore.'
        : '';

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value, type, checked } = e.target;
    if (name === 'basePath') setSaveError(null);
    setSettings(prev => ({
      ...prev,
      [name]: type === 'checkbox' ? checked : (type === 'number' ? parseInt(value, 10) : value),
    }));
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    setSaveError(null);
    try {
      await saveSettings(settings);
      onSave(settings);
    } catch (error) {
      // The host rejects a workspace path that is not on disk. That rejection is
      // the whole point of the validation, so it has to reach the operator.
      const message = error instanceof Error ? error.message : 'Failed to save settings.';
      setSaveError(message);
    } finally {
      setIsSaving(false);
    }
  };

  const handleConnectGitHub = async () => {
    if (!onConnectGitHub) return;
    const user = (settings.githubUser ?? '').trim();
    setConnectError(null);
    setConnectNotice(null);
    if (!user) {
      setConnectError('Enter a GitHub user or organization above first.');
      return;
    }
    setIsConnecting(true);
    try {
      await onConnectGitHub(user);
      setConnectNotice(`Connected as ${user}. The GitHub view is now available in the header toggle.`);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to connect to the GitHub API.';
      setConnectError(message);
    } finally {
      setIsConnecting(false);
    }
  };

  const fieldClass = 'mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm';

  return (
    <div className="fixed inset-0 z-50 flex items-start sm:items-center justify-center bg-black/60 p-2 sm:p-4 overflow-y-auto" onClick={onClose}>
      {/* Sized to the viewport rather than a fixed height: the body scrolls and
          the action footer stays reachable, so the dialog can never push Save
          off-screen the way the old fixed-height layout did on short windows.
          Wider on large screens so the settings use the horizontal space
          instead of forming one long column. */}
      <div
        className="bg-gray-800 rounded-lg shadow-xl w-full max-w-md md:max-w-3xl border border-gray-700 flex flex-col max-h-[95vh] my-auto"
        onClick={e => e.stopPropagation()}
        role="dialog"
        aria-label="Settings"
      >
        <form onSubmit={handleSave} className="flex flex-col min-h-0 flex-1">
          <div className="flex-shrink-0 px-6 pt-6 pb-3 border-b border-gray-700">
            <h2 className="text-xl font-bold text-white">Settings</h2>
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto px-6 py-4">
            {saveError && (
              <div data-testid="settings-save-error" role="alert" className="mb-4 rounded-md border border-red-600 bg-red-900/40 px-3 py-2 text-sm text-red-100">
                {saveError}
              </div>
            )}

            <div className="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-4">
              <div className="md:col-span-2">
                <label htmlFor="basePath" className="block text-sm font-medium text-gray-300">Workspace Path</label>
                <input type="text" name="basePath" id="basePath" value={settings.basePath} onChange={handleChange} className={fieldClass} />
                <p className="mt-1 text-xs text-gray-500">
                  The backend scans this folder for local git repositories. It must exist on the
                  machine running the host — a path that is not there is rejected on save.
                </p>
              </div>

              <div>
                <label htmlFor="scanDepth" className="block text-sm font-medium text-gray-300">Repository Scan Depth</label>
                <input type="number" name="scanDepth" id="scanDepth" value={settings.scanDepth} onChange={handleChange} min={1} max={6} className={fieldClass} />
                <p className="mt-1 text-xs text-gray-500">
                  How many folder levels to search under the workspace path for .git directories.
                </p>
              </div>

              <div>
                <label htmlFor="staleThreshold" className="block text-sm font-medium text-gray-300">Stale Threshold (days)</label>
                <input type="number" name="staleThreshold" id="staleThreshold" value={settings.staleThreshold} onChange={handleChange} className={fieldClass} />
                <p className="mt-1 text-xs text-gray-500">
                  A repository with no commits in this many days is counted as stale.
                </p>
              </div>

              {/* ── GitHub connection ─────────────────────────────────────────
                  Consolidated here from the former standalone "GitHub API"
                  dialog: the owner, the token variable, its live resolution, and
                  the connect action are one decision, so they belong on one
                  screen. */}
              <div className="md:col-span-2 pt-2 border-t border-gray-700">
                <h3 className="text-sm font-semibold text-gray-200">GitHub Connection</h3>
                <p className="mt-1 text-xs text-gray-500">
                  Queries GitHub metadata via the API. This never scans or transmits local files, and
                  tokens are never entered here — the host reads the environment variable named below.
                </p>
              </div>

              <div>
                <label htmlFor="githubUser" className="block text-sm font-medium text-gray-300">GitHub User/Org (default)</label>
                <input type="text" name="githubUser" id="githubUser" value={settings.githubUser ?? ''} onChange={handleChange} placeholder="e.g., octocat" className={fieldClass} />
                <p className="mt-1 text-xs text-gray-500">
                  Used by GitHub insights/reconcile when not supplied per-request.
                  Team-scoped queries are not supported in this build.
                </p>
                {onConnectGitHub && (
                  <div className="mt-2">
                    <button
                      type="button"
                      onClick={() => void handleConnectGitHub()}
                      disabled={isConnecting}
                      data-testid="connect-github-button"
                      className="px-3 py-1.5 text-xs font-semibold rounded border border-violet-600 bg-violet-900/50 text-violet-100 hover:bg-violet-800/60 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                    >
                      {isConnecting ? 'Connecting…' : 'Connect GitHub API'}
                    </button>
                    {connectedGitHubUser && (
                      <p className="mt-1.5 text-xs text-violet-300">Currently connected as {connectedGitHubUser}.</p>
                    )}
                    {connectError && <p className="mt-1.5 text-xs text-red-300">{connectError}</p>}
                    {connectNotice && <p className="mt-1.5 text-xs text-green-300">{connectNotice}</p>}
                  </div>
                )}
              </div>

              <div>
                <label htmlFor="gitHubTokenEnvVar" className="block text-sm font-medium text-gray-300">GitHub Token — Environment Variable Name</label>
                <input
                  type="text"
                  name="gitHubTokenEnvVar"
                  id="gitHubTokenEnvVar"
                  value={envVarName}
                  onChange={handleChange}
                  autoComplete="off"
                  spellCheck={false}
                  placeholder="GITHUB_TOKEN"
                  aria-invalid={Boolean(envVarNameError)}
                  aria-describedby="gitHubTokenEnvVarHelp"
                  className={`mt-1 block w-full bg-gray-900 border rounded-md shadow-sm py-2 px-3 text-white font-mono focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm ${envVarNameError ? 'border-red-500' : 'border-gray-600'}`}
                />
                <div id="gitHubTokenEnvVarHelp" className="mt-1 space-y-1 text-xs text-gray-500">
                  <p className="text-amber-300/90">
                    Enter the <strong>name</strong> of the variable, not the token.
                  </p>
                  <p>
                    Needs: <code>Metadata: Read</code>, <code>Contents: Read and write</code>,{' '}
                    <code>Pull requests: Read and write</code>, <code>Actions: Read</code>, and{' '}
                    <code>Checks: Read</code> for per-check merge detail.
                  </p>
                  <p>
                    {authStatus?.runningAsService
                      ? 'This host runs as a service, so the variable must be set at Machine scope — a User-scoped variable is invisible to it. Restart the service after setting it.'
                      : 'Set the variable before launching the host; one set after launch is not picked up until restart.'}
                  </p>
                </div>

                {envVarNameError && (
                  <p className="mt-2 text-xs text-red-300">{envVarNameError}</p>
                )}
              </div>

              <div className="md:col-span-2">
                <div className="rounded-md border border-gray-700 bg-gray-900/50 p-3">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-xs font-medium text-gray-300">Resolution on the host</span>
                    <button
                      type="button"
                      onClick={() => void refreshAuthStatus(true)}
                      disabled={isChecking}
                      className="text-xs text-blue-400 hover:text-blue-300 disabled:text-gray-500"
                    >
                      {isChecking ? 'Checking…' : 'Test connection'}
                    </button>
                  </div>

                  {envVarNameChanged && (
                    <p className="mt-2 text-xs text-amber-300">
                      Save, then restart the host before testing — the status below still reflects
                      the previously saved name.
                    </p>
                  )}

                  {!authStatus && !isChecking && (
                    <p className="mt-2 text-xs text-gray-500">Status unavailable.</p>
                  )}

                  {authStatus && (
                    <div className="mt-2 space-y-1 text-xs">
                      <p className={authStatus.tokenSource === 'none' ? 'text-red-300' : 'text-green-300'}>
                        {authStatus.tokenSource === 'env'
                          ? `Resolved from ${authStatus.tokenEnvVar} (${authStatus.tokenEnvScope} scope).`
                          : authStatus.tokenSource === 'gh-cli'
                            ? `${authStatus.tokenEnvVar} is empty — falling back to the gh CLI credential.`
                            : `${authStatus.tokenEnvVar} did not resolve. GitHub calls run unauthenticated.`}
                      </p>
                      {authStatus.hint && <p className="text-amber-300">{authStatus.hint}</p>}
                      {authStatus.liveCheck?.checked && (
                        <p className={authStatus.liveCheck.valid ? 'text-green-300' : 'text-red-300'}>
                          {authStatus.liveCheck.valid
                            ? `Token is live as ${authStatus.liveCheck.login}${authStatus.liveCheck.expiresAt ? ` — expires ${authStatus.liveCheck.expiresAt}` : ''}.`
                            : authStatus.liveCheck.error}
                        </p>
                      )}
                    </div>
                  )}
                </div>
              </div>

              {/* ── Archiving and output ───────────────────────────────────── */}
              <div className="md:col-span-2 pt-2 border-t border-gray-700">
                <h3 className="text-sm font-semibold text-gray-200">Archiving and Output</h3>
              </div>

              <div>
                <label htmlFor="daysInactive" className="block text-sm font-medium text-gray-300">Days Inactive for Archive</label>
                <input type="number" name="daysInactive" id="daysInactive" value={settings.daysInactive} onChange={handleChange} className={fieldClass} />
                <div className="mt-2 flex items-center">
                  <input id="zipArchive" name="zipArchive" type="checkbox" checked={settings.zipArchive} onChange={handleChange} className="h-4 w-4 text-blue-600 bg-gray-700 border-gray-600 rounded focus:ring-blue-500" />
                  <label htmlFor="zipArchive" className="ml-2 block text-sm text-gray-300">Zip on Archive</label>
                </div>
              </div>

              <div>
                <label htmlFor="reportPath" className="block text-sm font-medium text-gray-300">Report Folder</label>
                <input type="text" name="reportPath" id="reportPath" value={settings.reportPath} readOnly disabled className="mt-1 block w-full bg-gray-900/60 border border-gray-700 rounded-md shadow-sm py-2 px-3 text-gray-400 cursor-not-allowed sm:text-sm" />
                <p className="mt-1 text-xs text-gray-500">
                  Dashboard exports are saved in the repo-local <code>reports</code> folder with timestamped filenames.
                </p>
              </div>
            </div>
          </div>

          <div className="flex-shrink-0 bg-gray-700/50 px-6 py-3 flex justify-end space-x-3 border-t border-gray-700">
            <button type="button" onClick={onClose} className="py-2 px-4 text-sm font-medium rounded-md text-gray-300 bg-gray-600 hover:bg-gray-500 transition-colors">
              Cancel
            </button>
            <button type="submit" disabled={isSaving || Boolean(envVarNameError)} title={envVarNameError ? `Fix the environment variable name first: ${envVarNameError}` : isSaving ? 'Settings are being saved.' : 'Saves these settings.'} className="py-2 px-4 text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 transition-colors disabled:opacity-50">
              {isSaving ? 'Saving...' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default SettingsModal;
