
import React, { useState, useEffect, useCallback } from 'react';
import { type AppSettings, type GitHubAuthStatus } from '../types';
import { saveSettings, getGitHubAuthStatus } from '../services/apiClient';

interface SettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (settings: AppSettings) => void;
  currentSettings: AppSettings;
}

const ENV_VAR_NAME_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*$/;
const TOKEN_LOOKALIKE_PATTERN = /^(gh[pousr]_|github_pat_)/;

const SettingsModal: React.FC<SettingsModalProps> = ({ isOpen, onClose, onSave, currentSettings }) => {
  const [settings, setSettings] = useState<AppSettings>(currentSettings);
  const [isSaving, setIsSaving] = useState(false);
  const [authStatus, setAuthStatus] = useState<GitHubAuthStatus | null>(null);
  const [isChecking, setIsChecking] = useState(false);

  useEffect(() => {
    setSettings(currentSettings);
  }, [currentSettings]);

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
    setSettings(prev => ({
      ...prev,
      [name]: type === 'checkbox' ? checked : (type === 'number' ? parseInt(value, 10) : value),
    }));
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    try {
      await saveSettings(settings);
      onSave(settings);
    } catch (error) {
      console.error("Failed to save settings", error);
      // Here you would show a toast to the user
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" onClick={onClose}>
      <div className="bg-gray-800 rounded-lg shadow-xl w-full max-w-md border border-gray-700" onClick={e => e.stopPropagation()}>
        <form onSubmit={handleSave}>
          <div className="p-6">
            <h2 className="text-xl font-bold text-white mb-4">Settings</h2>
            <div className="space-y-4">
              <div>
                <label htmlFor="basePath" className="block text-sm font-medium text-gray-300">Workspace Path</label>
                <input type="text" name="basePath" id="basePath" value={settings.basePath} onChange={handleChange} className="mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" />
                <p className="mt-1 text-xs text-gray-500">
                  The backend scans this folder for local git repositories.
                </p>
              </div>
              <div>
                <label htmlFor="scanDepth" className="block text-sm font-medium text-gray-300">Repository Scan Depth</label>
                <input type="number" name="scanDepth" id="scanDepth" value={settings.scanDepth} onChange={handleChange} min={1} max={6} className="mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" />
                <p className="mt-1 text-xs text-gray-500">
                  How many folder levels to search under the workspace path for .git directories.
                </p>
              </div>
              <div>
                <label htmlFor="githubUser" className="block text-sm font-medium text-gray-300">GitHub User/Org (default)</label>
                <input type="text" name="githubUser" id="githubUser" value={settings.githubUser ?? ''} onChange={handleChange} className="mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" />
                <p className="mt-1 text-xs text-gray-500">
                  Used by GitHub insights/reconcile when not supplied per-request.
                </p>
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
                    Enter the <strong>name</strong> of the variable, not the token. This app never
                    stores your token — it reads the named variable at runtime.
                  </p>
                  <p>
                    The token needs these fine-grained permissions: <code>Metadata: Read</code>,{' '}
                    <code>Contents: Read and write</code>, <code>Pull requests: Read and write</code>,{' '}
                    <code>Actions: Read</code>, and <code>Checks: Read</code> for per-check merge detail.
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

                <div className="mt-2 rounded-md border border-gray-700 bg-gray-900/50 p-3">
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
              <div>
                <label htmlFor="reportPath" className="block text-sm font-medium text-gray-300">Report Folder</label>
                <input type="text" name="reportPath" id="reportPath" value={settings.reportPath} readOnly disabled className="mt-1 block w-full bg-gray-900/60 border border-gray-700 rounded-md shadow-sm py-2 px-3 text-gray-400 cursor-not-allowed sm:text-sm" />
                <p className="mt-1 text-xs text-gray-500">
                  Dashboard exports are saved in the repo-local <code>reports</code> folder with timestamped filenames.
                </p>
              </div>
              <div>
                <label htmlFor="staleThreshold" className="block text-sm font-medium text-gray-300">Stale Threshold (days)</label>
                <input type="number" name="staleThreshold" id="staleThreshold" value={settings.staleThreshold} onChange={handleChange} className="mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" />
              </div>
              <div>
                <label htmlFor="daysInactive" className="block text-sm font-medium text-gray-300">Days Inactive for Archive</label>
                <input type="number" name="daysInactive" id="daysInactive" value={settings.daysInactive} onChange={handleChange} className="mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" />
              </div>
              <div className="flex items-center">
                <input id="zipArchive" name="zipArchive" type="checkbox" checked={settings.zipArchive} onChange={handleChange} className="h-4 w-4 text-blue-600 bg-gray-700 border-gray-600 rounded focus:ring-blue-500" />
                <label htmlFor="zipArchive" className="ml-2 block text-sm text-gray-300">Zip on Archive</label>
              </div>
            </div>
          </div>
          <div className="bg-gray-700/50 px-6 py-3 flex justify-end space-x-3">
            <button type="button" onClick={onClose} className="py-2 px-4 text-sm font-medium rounded-md text-gray-300 bg-gray-600 hover:bg-gray-500 transition-colors">
              Cancel
            </button>
            <button type="submit" disabled={isSaving || Boolean(envVarNameError)} className="py-2 px-4 text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 transition-colors disabled:opacity-50">
              {isSaving ? 'Saving...' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default SettingsModal;
