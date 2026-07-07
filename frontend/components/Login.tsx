import React, { useState } from 'react';
import { AuthStatus, login, setApiKey, getAuthStatus } from '../services/apiClient';

interface LoginProps {
  status: AuthStatus;
  onAuthenticated: () => void;
}

// Release 2.7 — gate shown when the portal requires auth and the browser is not
// yet authenticated. Two paths:
//  * password: a portal login has been configured -> exchange it for a session
//    cookie (the normal human flow).
//  * apiKey: only the shared API key is in play (no login set yet) -> paste the
//    key once; it is stored and sent on every request.
const Login: React.FC<LoginProps> = ({ status, onAuthenticated }) => {
  const [mode, setMode] = useState<'password' | 'apiKey'>(status.loginConfigured ? 'password' : 'apiKey');
  const [value, setValue] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      if (mode === 'password') {
        await login(value);
        onAuthenticated();
      } else {
        setApiKey(value.trim());
        const next = await getAuthStatus();
        if (next.authenticated) {
          onAuthenticated();
        } else {
          setApiKey('');
          setError('That API key was not accepted.');
        }
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign-in failed.');
    } finally {
      setSubmitting(false);
    }
  };

  const isPassword = mode === 'password';

  return (
    <div className="min-h-screen bg-gray-900 text-gray-200 font-sans flex items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <div className="flex items-center justify-center mb-6">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-9 w-9 text-blue-400 mr-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"></path></svg>
          <h1 className="text-xl font-bold text-gray-100">GitHub Repo Manager</h1>
        </div>

        <form
          onSubmit={handleSubmit}
          className="bg-gray-800/60 border border-gray-700 rounded-lg p-6 shadow-xl"
          data-testid="login-form"
        >
          <h2 className="text-base font-semibold text-gray-100 mb-1">
            {isPassword ? 'Sign in' : 'Enter API key'}
          </h2>
          <p className="text-xs text-gray-400 mb-4">
            {isPassword
              ? 'This portal is protected. Enter your operator password to continue.'
              : 'This portal requires an API key. Paste it once — it is stored in this browser.'}
          </p>

          <label htmlFor="login-secret" className="sr-only">
            {isPassword ? 'Password' : 'API key'}
          </label>
          <input
            id="login-secret"
            type="password"
            autoFocus
            autoComplete={isPassword ? 'current-password' : 'off'}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder={isPassword ? 'Password' : 'API key'}
            className="w-full px-3 py-2 rounded-md bg-gray-900 border border-gray-600 text-gray-100 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            disabled={submitting}
          />

          {error && (
            <p className="mt-3 text-sm text-red-400" role="alert" data-testid="login-error">{error}</p>
          )}

          <button
            type="submit"
            disabled={submitting || value.length === 0}
            className="mt-4 w-full px-4 py-2 rounded-md bg-blue-600 text-white font-medium hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {submitting ? 'Signing in…' : 'Sign in'}
          </button>

          {status.loginConfigured && status.authEnforced && (
            <button
              type="button"
              onClick={() => { setMode(isPassword ? 'apiKey' : 'password'); setValue(''); setError(null); }}
              className="mt-3 w-full text-xs text-gray-400 hover:text-gray-200 transition-colors"
            >
              {isPassword ? 'Use an API key instead' : 'Use your password instead'}
            </button>
          )}
        </form>

        <p className="mt-4 text-center text-xs text-gray-600">
          {status.isLoopbackBind ? 'Local access' : `Serving ${status.bindAddress ?? ''}`}
        </p>
      </div>
    </div>
  );
};

export default Login;
