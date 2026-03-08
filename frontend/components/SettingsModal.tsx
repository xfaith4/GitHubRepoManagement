
import React, { useState, useEffect } from 'react';
import { type AppSettings } from '../types';
import { saveSettings } from '../services/apiClient';

interface SettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (settings: AppSettings) => void;
  currentSettings: AppSettings;
}

const SettingsModal: React.FC<SettingsModalProps> = ({ isOpen, onClose, onSave, currentSettings }) => {
  const [settings, setSettings] = useState<AppSettings>(currentSettings);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    setSettings(currentSettings);
  }, [currentSettings]);

  if (!isOpen) return null;

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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" onClick={onClose}>
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
                <label htmlFor="githubToken" className="block text-sm font-medium text-gray-300">GitHub Token (fallback)</label>
                <input type="password" name="githubToken" id="githubToken" value={settings.githubToken ?? ''} onChange={handleChange} autoComplete="off" className="mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" />
                <p className="mt-1 text-xs text-gray-500">
                  Preferred source is environment variable <code>GITHUB_TOKEN</code>. This field is used only if env var is not set.
                </p>
              </div>
              <div>
                <label htmlFor="reportPath" className="block text-sm font-medium text-gray-300">Report Path</label>
                <input type="text" name="reportPath" id="reportPath" value={settings.reportPath} onChange={handleChange} className="mt-1 block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" />
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
            <button type="submit" disabled={isSaving} className="py-2 px-4 text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 transition-colors disabled:opacity-50">
              {isSaving ? 'Saving...' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default SettingsModal;
