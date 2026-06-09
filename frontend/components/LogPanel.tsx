import React, { useEffect, useRef } from 'react';
import { type OperationType } from '../types';
import { SpinnerIcon } from './icons';

interface LogPanelProps {
  isOpen: boolean;
  operation: OperationType | null;
  messages: string[];
  status: 'idle' | 'running' | 'success' | 'error';
  progressSummary?: string;
  onClose: () => void;
}

const LogPanel: React.FC<LogPanelProps> = ({ isOpen, operation, messages, status, progressSummary, onClose }) => {
  const logsEndRef = useRef<HTMLDivElement>(null);

  const operationTitle = operation === 'scan' ? 'Scan Progress' : (operation ? operation.charAt(0).toUpperCase() + operation.slice(1) : 'Operation');

  useEffect(() => {
    logsEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  return (
    <>
      <div 
        className={`fixed inset-0 bg-black/60 z-30 transition-opacity ${isOpen ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        onClick={onClose}
      />
      <div
        className={`fixed top-0 right-0 h-full w-full max-w-lg bg-gray-900 shadow-2xl z-40 transform transition-transform duration-300 ease-in-out ${
          isOpen ? 'translate-x-0' : 'translate-x-full'
        }`}
      >
        <div className="flex flex-col h-full">
          <header className="flex items-center justify-between p-4 border-b border-gray-700 bg-gray-800">
            <div>
              <h2 className="text-lg font-semibold">{operationTitle} Log</h2>
              {progressSummary && <p className="text-xs text-gray-400 mt-1">{progressSummary}</p>}
            </div>
            <button onClick={onClose} className="p-1 rounded-full text-gray-400 hover:bg-gray-700 hover:text-white transition-colors">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </header>
          <div className="flex-grow p-4 overflow-y-auto bg-black/20">
            <pre className="text-xs text-gray-300 whitespace-pre-wrap font-mono">
              {messages.map((msg, index) => (
                <div key={index}>{`> ${msg}`}</div>
              ))}
              <div ref={logsEndRef} />
            </pre>
          </div>
          <footer className="p-3 text-sm text-center border-t border-gray-700 bg-gray-800">
            {status === 'running' && (
              <p className="text-yellow-400 flex items-center justify-center gap-2">
                <SpinnerIcon className="w-4 h-4" />
                Operation in progress...
              </p>
            )}
            {status === 'success' && <p className="text-green-400">Operation completed successfully.</p>}
            {status === 'error' && <p className="text-red-400">Operation finished with errors.</p>}
            {status === 'idle' && (
              <p className="text-gray-400">No active operation.</p>
            )}
          </footer>
        </div>
      </div>
    </>
  );
};

export default LogPanel;
