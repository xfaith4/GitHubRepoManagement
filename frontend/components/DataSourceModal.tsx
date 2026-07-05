import React, { useEffect, useState } from 'react';

interface DataSourceModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (username: string, apiKey?: string) => void;
  currentUsername?: string;
}

const DataSourceModal: React.FC<DataSourceModalProps> = ({ isOpen, onClose, onSave, currentUsername }) => {
  const [username, setUsername] = useState(currentUsername || '');
  const [apiKey, setApiKey] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    setUsername(currentUsername || '');
  }, [currentUsername, isOpen]);

  if (!isOpen) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    
    if (!username.trim()) {
      setError("GitHub username/organization is required.");
      return;
    }
    
    setIsSubmitting(true);
    try {
      await onSave(username.trim(), apiKey.trim());
      onClose();
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to apply data source configuration.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleClose = () => {
    setUsername(currentUsername || '');
    setApiKey('');
    setError('');
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" onClick={handleClose}>
      <div className="bg-gray-800 rounded-lg shadow-xl w-full max-w-md border border-gray-700" onClick={e => e.stopPropagation()}>
        <form onSubmit={handleSubmit}>
          <div className="p-6">
            <h2 className="text-xl font-bold text-white mb-4">Connect GitHub API</h2>
            <p className="text-sm text-gray-400 mb-4">
              Enter a GitHub username or organization to query GitHub metadata via the GitHub API. The token field is optional when <code>GITHUB_TOKEN</code> is already set before launch or a fallback token is saved in Settings.
            </p>
            <p className="text-xs text-gray-500 mb-4">
              This workflow does not scan or transmit local files. Any token entered here is stored in memory for this session only.
            </p>
            {error && (
              <div className="mb-4 p-3 bg-red-900/50 border border-red-700 rounded-md text-sm text-red-200">
                {error}
              </div>
            )}
            <div className="space-y-4">
              <div>
                <label htmlFor="username" className="block text-sm font-medium text-gray-300">
                  GitHub Username or Organization
                </label>
                <input 
                  type="text" 
                  name="username" 
                  id="username" 
                  value={username} 
                  onChange={(e) => setUsername(e.target.value)} 
                  required
                  placeholder="e.g., octocat or github"
                  className="mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" 
                />
                <p className="mt-1 text-xs text-gray-500">
                  Team-scoped queries are not supported in this build.
                </p>
              </div>
              
              <div>
                <label htmlFor="apiKey" className="block text-sm font-medium text-gray-300">
                  GitHub Personal Access Token (optional)
                </label>
                <input 
                  type="password" 
                  name="apiKey" 
                  id="apiKey" 
                  value={apiKey} 
                  onChange={(e) => setApiKey(e.target.value)}
                  autoComplete="off"
                  className="mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  placeholder="ghp_..."
                />
                <p className="mt-2 text-xs text-gray-500">
                  Token source priority: entered token, then environment variable <code>GITHUB_TOKEN</code>, then Settings fallback token.
                </p>
              </div>
            </div>
          </div>
          <div className="bg-gray-700/50 px-6 py-3 flex justify-end space-x-3">
            <button 
              type="button" 
              onClick={handleClose} 
              className="py-2 px-4 text-sm font-medium rounded-md text-gray-300 bg-gray-600 hover:bg-gray-500 transition-colors"
            >
              Cancel
            </button>
            <button 
              type="submit" 
              disabled={isSubmitting} 
              className="py-2 px-4 text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 transition-colors disabled:opacity-50"
            >
              {isSubmitting ? 'Applying...' : 'Apply'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default DataSourceModal;
