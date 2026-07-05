import React, { useState, useEffect, useCallback } from 'react';
import { getSetupPrerequisites, submitSetupConfig, setApiKey, type SetupPrerequisite } from '../services/apiClient';

interface SetupWizardProps {
  onComplete: () => void;
}

type Step = 1 | 2 | 3 | 4;

// Release 2.2 — four-step guided first-run setup: prerequisites, local roots,
// GitHub auth mode, and first-scan confirmation. Rendered by App when
// /setup/status reports needsSetup (or with ?setup=1 to preview).
function SetupWizard({ onComplete }: SetupWizardProps) {
  const [step, setStep] = useState<Step>(1);
  const [prereqs, setPrereqs] = useState<SetupPrerequisite[]>([]);
  const [prereqsMet, setPrereqsMet] = useState(false);
  const [prereqLoading, setPrereqLoading] = useState(true);
  const [localRootsText, setLocalRootsText] = useState('');
  const [gitHubOwner, setGitHubOwner] = useState('');
  const [requireApiKey, setRequireApiKey] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [generatedKey, setGeneratedKey] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    getSetupPrerequisites()
      .then(res => { if (!cancelled) { setPrereqs(res.checks); setPrereqsMet(res.prerequisitesMet); } })
      .catch(err => { if (!cancelled) setError(err instanceof Error ? err.message : 'Failed to load prerequisites'); })
      .finally(() => { if (!cancelled) setPrereqLoading(false); });
    return () => { cancelled = true; };
  }, []);

  const roots = localRootsText.split('\n').map(r => r.trim()).filter(Boolean);

  const handleSubmit = useCallback(async () => {
    setSubmitting(true);
    setError(null);
    try {
      const result = await submitSetupConfig({
        localRoots: roots,
        gitHubOwner: gitHubOwner.trim() || undefined,
        requireApiKey,
      });
      if (result.generatedApiKey) {
        setGeneratedKey(result.generatedApiKey);
        setApiKey(result.generatedApiKey);
      }
      // First scan is triggered by the app re-mounting after setup completes.
      onComplete();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Setup failed');
    } finally {
      setSubmitting(false);
    }
  }, [roots, gitHubOwner, requireApiKey, onComplete]);

  const stepTitles = ['Prerequisites', 'Local roots', 'GitHub auth', 'Confirm'];

  return (
    <div className="min-h-screen bg-gray-900 text-gray-200 flex items-center justify-center p-4">
      <div className="w-full max-w-xl bg-gray-800/60 border border-gray-700 rounded-xl p-6" role="dialog" aria-label="Setup Wizard">
        <h1 className="text-xl font-bold text-white mb-1">Welcome — let’s set up GitHub Repo Manager</h1>
        <p className="text-sm text-gray-400 mb-4">Step {step} of 4 · {stepTitles[step - 1]}</p>

        <div className="flex gap-1 mb-6" aria-hidden="true">
          {[1, 2, 3, 4].map(n => (
            <div key={n} className={`h-1.5 flex-1 rounded-full ${n <= step ? 'bg-indigo-500' : 'bg-gray-700'}`} />
          ))}
        </div>

        {error && <div className="mb-4 rounded-md border border-red-800 bg-red-900/40 px-3 py-2 text-sm text-red-200">{error}</div>}

        {step === 1 && (
          <div className="space-y-3">
            <p className="text-sm text-gray-300">Checking your environment.</p>
            {prereqLoading ? (
              <p className="text-sm text-gray-500">Loading prerequisites…</p>
            ) : (
              <ul className="space-y-1.5">
                {prereqs.map(c => (
                  <li key={c.id} className="flex items-center gap-2 text-sm">
                    <span className={c.ok ? 'text-green-400' : (c.required ? 'text-red-400' : 'text-yellow-400')}>{c.ok ? '✓' : (c.required ? '✕' : '!')}</span>
                    <span className="text-gray-200">{c.label}</span>
                    {c.detail ? <span className="text-gray-500 text-xs">({c.detail})</span> : null}
                    {!c.required ? <span className="text-gray-600 text-xs">optional</span> : null}
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}

        {step === 2 && (
          <div className="space-y-2">
            <label className="text-sm text-gray-300">Local workspace roots to scan (one path per line):</label>
            <textarea
              value={localRootsText}
              onChange={e => setLocalRootsText(e.target.value)}
              rows={4}
              placeholder={'C:\\Development\nD:\\repos'}
              className="w-full rounded-md bg-gray-900 border border-gray-700 px-3 py-2 text-sm text-gray-100 font-mono"
            />
            <p className="text-xs text-gray-500">{roots.length} root{roots.length === 1 ? '' : 's'} entered.</p>
          </div>
        )}

        {step === 3 && (
          <div className="space-y-3">
            <div>
              <label className="text-sm text-gray-300">GitHub owner/username (optional):</label>
              <input
                value={gitHubOwner}
                onChange={e => setGitHubOwner(e.target.value)}
                placeholder="your-github-username"
                className="mt-1 w-full rounded-md bg-gray-900 border border-gray-700 px-3 py-2 text-sm text-gray-100"
              />
              <p className="text-xs text-gray-500 mt-1">Auth uses your <code>GITHUB_TOKEN</code> env var or the <code>gh</code> CLI. GitHub App OAuth is optional.</p>
            </div>
            <label className="flex items-center gap-2 text-sm text-gray-300">
              <input type="checkbox" checked={requireApiKey} onChange={e => setRequireApiKey(e.target.checked)} />
              Require an API key for this host (recommended before LAN sharing)
            </label>
          </div>
        )}

        {step === 4 && (
          <div className="space-y-2 text-sm text-gray-300">
            <p>Ready to write <code>settings.json</code> and run the first scan.</p>
            <ul className="text-gray-400 list-disc pl-5">
              <li>{roots.length} local root{roots.length === 1 ? '' : 's'}</li>
              <li>GitHub owner: {gitHubOwner.trim() || '(none)'}</li>
              <li>API key required: {requireApiKey ? 'yes' : 'no'}</li>
            </ul>
            {generatedKey && (
              <div className="rounded-md border border-indigo-800 bg-indigo-900/30 px-3 py-2 text-xs text-indigo-200 break-all">
                Generated API key (saved to this browser): {generatedKey}
              </div>
            )}
          </div>
        )}

        <div className="flex justify-between mt-6">
          <button
            onClick={() => setStep((s) => (s > 1 ? (s - 1) as Step : s))}
            disabled={step === 1 || submitting}
            className="px-4 py-2 rounded-md text-sm bg-gray-700 text-gray-300 disabled:opacity-40"
          >
            Back
          </button>
          {step < 4 ? (
            <button
              onClick={() => setStep((s) => (s + 1) as Step)}
              disabled={(step === 2 && roots.length === 0)}
              className="px-4 py-2 rounded-md text-sm bg-indigo-600 text-white disabled:opacity-40"
            >
              Next
            </button>
          ) : (
            <button
              onClick={handleSubmit}
              disabled={submitting || roots.length === 0}
              className="px-4 py-2 rounded-md text-sm bg-green-600 text-white disabled:opacity-40"
            >
              {submitting ? 'Setting up…' : 'Finish & scan'}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

export default SetupWizard;
