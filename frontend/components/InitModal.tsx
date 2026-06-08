import React, { useState } from 'react';

interface InitModalProps {
  isOpen: boolean;
  onClose: () => void;
  onInit: (githubUser: string, cloneOwned: boolean, apiKey?: string, basePath?: string) => void;
}

const InitModal: React.FC<InitModalProps> = ({ isOpen, onClose, onInit }) => {
  const [githubUser, setGithubUser] = useState('');
  const [cloneOwned, setCloneOwned] = useState(true);
  const [apiKey, setApiKey] = useState('');
  const [basePath, setBasePath] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    alert('Clone is a planned feature and is not implemented in this build.');
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" onClick={onClose}>
      <div className="bg-gray-800 rounded-lg shadow-xl w-full max-w-md border border-gray-700" onClick={e => e.stopPropagation()}>
        <form onSubmit={handleSubmit}>
          <div className="p-6">
            <h2 className="text-xl font-bold text-white mb-4">Clone from GitHub (Planned)</h2>
            <p className="text-sm text-gray-400 mb-4">
              Planned feature: clone repositories from GitHub into a local workspace using the local backend. This is not implemented in this build.
            </p>
            <div className="space-y-4">
              <div>
                <label htmlFor="githubUser" className="block text-sm font-medium text-gray-300">GitHub Username</label>
                <input 
                  type="text" 
                  name="githubUser" 
                  id="githubUser" 
                  value={githubUser} 
                  onChange={(e) => setGithubUser(e.target.value)} 
                  required
                  className="mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" 
                />
              </div>
              
              <div className="flex items-center">
                <input 
                  id="cloneOwned" 
                  name="cloneOwned" 
                  type="checkbox" 
                  checked={cloneOwned} 
                  onChange={(e) => setCloneOwned(e.target.checked)} 
                  className="h-4 w-4 text-blue-600 bg-gray-700 border-gray-600 rounded focus:ring-blue-500" 
                />
                <label htmlFor="cloneOwned" className="ml-2 block text-sm text-gray-300">Clone repositories from GitHub</label>
              </div>

              {cloneOwned && (
                 <>
                    <div>
                        <label htmlFor="apiKey" className="block text-sm font-medium text-gray-300">GitHub Personal Access Token</label>
                        <input 
                            type="password" 
                            name="apiKey" 
                            id="apiKey" 
                            value={apiKey} 
                            onChange={(e) => setApiKey(e.target.value)}
                            required 
                            autoComplete="new-password"
                            className="mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                            placeholder="ghp_..."
                        />
                        <p className="mt-2 text-xs text-gray-500">
                            A token with 'repo' scope is required. This is sent to your local backend to perform the clone operation.
                        </p>
                    </div>
                    <div>
                        <label htmlFor="basePath" className="block text-sm font-medium text-gray-300">Local Workspace Path (Optional)</label>
                        <div className="mt-1 flex rounded-md shadow-sm">
                            <input
                                type="text"
                                name="basePath"
                                id="basePath"
                                value={basePath}
                                onChange={(e) => setBasePath(e.target.value)}
                                className="flex-1 block w-full min-w-0 bg-gray-900 border border-gray-600 rounded-md py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                                placeholder="e.g., G:\\Development"
                            />
                        </div>
                        <p className="mt-2 text-xs text-gray-500">
                           This is a local filesystem path on the machine running the backend (not a browser folder selection).
                        </p>
                    </div>
                 </>
              )}
            </div>
          </div>
          <div className="bg-gray-700/50 px-6 py-3 flex justify-end space-x-3">
            <button type="button" onClick={onClose} className="py-2 px-4 text-sm font-medium rounded-md text-gray-300 bg-gray-600 hover:bg-gray-500 transition-colors">
              Cancel
            </button>
            <button type="submit" disabled={true} className="py-2 px-4 text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 transition-colors disabled:opacity-50">
              Not Available
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default InitModal;
