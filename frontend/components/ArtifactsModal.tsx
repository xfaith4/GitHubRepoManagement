import React, { useState, useEffect } from 'react';
import { getArtifacts } from '../services/apiClient';
import { type Artifact } from '../types';
import { SpinnerIcon } from './icons';

interface ArtifactsModalProps {
  isOpen: boolean;
  onClose: () => void;
  repoName: string | null;
}

const ArtifactsModal: React.FC<ArtifactsModalProps> = ({ isOpen, onClose, repoName }) => {
  const [artifacts, setArtifacts] = useState<Artifact[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (isOpen && repoName) {
      setLoading(true);
      setError(null);
      setArtifacts([]);
      getArtifacts(repoName)
        .then(data => setArtifacts(data))
        .catch(() => setError('Failed to load artifacts.'))
        .finally(() => setLoading(false));
    }
  }, [isOpen, repoName]);

  if (!isOpen) return null;

  const formatBytes = (bytes: number, decimals = 2) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" onClick={onClose}>
      <div className="bg-gray-800 rounded-lg shadow-xl w-full max-w-2xl border border-gray-700" onClick={e => e.stopPropagation()}>
        <div className="p-6">
          <div className="flex justify-between items-center">
            <h2 className="text-xl font-bold text-white">Artifacts for: <span className="text-blue-400">{repoName}</span></h2>
             <button onClick={onClose} className="p-1 rounded-full text-gray-400 hover:bg-gray-700 hover:text-white transition-colors">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          <div className="mt-4 max-h-96 overflow-y-auto">
            {loading && <div className="flex justify-center items-center p-8"><SpinnerIcon className="w-8 h-8 text-blue-400" /></div>}
            {error && <p className="text-red-400 text-center">{error}</p>}
            {!loading && !error && artifacts.length === 0 && <p className="text-gray-400 text-center">No artifacts found.</p>}
            {!loading && !error && artifacts.length > 0 && (
              <table className="min-w-full divide-y divide-gray-700">
                <thead className="bg-gray-700/50">
                  <tr>
                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Name</th>
                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Size</th>
                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Created At</th>
                    <th scope="col" className="relative px-6 py-3"><span className="sr-only">Open</span></th>
                  </tr>
                </thead>
                <tbody className="bg-gray-800 divide-y divide-gray-700">
                  {artifacts.map(artifact => (
                    <tr key={artifact.name}>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-200">{artifact.name}</td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-400">{formatBytes(artifact.size)}</td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-400">{new Date(artifact.createdAt).toLocaleString()}</td>
                      <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                        <a href={artifact.downloadUrl} target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:text-blue-300">Open</a>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
        <div className="bg-gray-700/50 px-6 py-3 flex justify-end">
            <button type="button" onClick={onClose} className="py-2 px-4 text-sm font-medium rounded-md text-gray-300 bg-gray-600 hover:bg-gray-500 transition-colors">
              Close
            </button>
        </div>
      </div>
    </div>
  );
};

export default ArtifactsModal;
