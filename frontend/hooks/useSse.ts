import { useState, useEffect, useRef } from 'react';

const USE_MOCK_API = (() => {
  const env = typeof import.meta !== 'undefined' ? import.meta.env : undefined;
  const value = (env?.VITE_USE_MOCK_API as string | undefined) ?? 'false';
  return value === 'true' || value === '1';
})();

export enum SseStatus {
  CONNECTING = 'CONNECTING',
  OPEN = 'OPEN',
  CLOSED = 'CLOSED',
  ERROR = 'ERROR',
}

export const useSse = (url: string | null) => {
  const [messages, setMessages] = useState<string[]>([]);
  const [status, setStatus] = useState<SseStatus>(SseStatus.CLOSED);
  const timeoutsRef = useRef<ReturnType<typeof setTimeout>[]>([]);

  useEffect(() => {
    // Clear any previous simulation on URL change
    timeoutsRef.current.forEach(clearTimeout);
    timeoutsRef.current = [];
    
    if (!url) {
      setStatus(SseStatus.CLOSED);
      setMessages([]);
      return;
    }

    if (!USE_MOCK_API) {
      // --- Real EventSource implementation ---
      setMessages([]);
      setStatus(SseStatus.CONNECTING);

      const eventSource = new EventSource(url);

      eventSource.onopen = () => {
        setStatus(SseStatus.OPEN);
      };

      eventSource.onmessage = (event) => {
        setMessages(prev => [...prev, event.data]);
      };

      eventSource.onerror = () => {
        setStatus(SseStatus.ERROR);
        eventSource.close();
      };

      return () => {
        eventSource.close();
        setStatus(SseStatus.CLOSED);
      };
    }

    // --- Mock SSE Stream ---
    // Simulates a live log stream for the frontend-only demo.
    const isScan = url.includes('scan') || url.includes('status');
    const operation = url.split('/').pop() || 'operation';

    const mockLogs = isScan ? [
      'Initialising workspace scanner...',
      'Loading configuration settings...',
      'Resolving local repository roots...',
      'Traversing directory tree (depth 2)...',
      'Discovered 3 candidate directories.',
      'Checking git status for: project-alpha ... clean',
      'Checking git status for: internal-tools ... 2 modified files',
      'Checking git status for: legacy-system ... clean',
      'Collecting last commit metadata...',
      'Scan complete.',
    ] : [
      `Starting: ${operation}...`,
      `Authenticating with provided credentials... OK`,
      `Locating base path... OK`,
      `Analysing repositories for ${operation}...`,
      `Found 5 repositories to process.`,
      `[1/5] Processing project-alpha... done.`,
      `[2/5] Processing internal-tools... done.`,
      `[3/5] Processing legacy-system... WARNING: outdated dependencies detected.`,
      `[4/5] Processing mobile-app-sdk... done.`,
      `[5/5] Processing archived-project... SKIPPED.`,
      `Operation '${operation}' completed successfully.`,
      `Summary: 4 processed, 1 skipped, 1 warning.`,
    ];

    setStatus(SseStatus.CONNECTING);
    setMessages([]);
    
    const connectTimeout = setTimeout(() => {
      setStatus(SseStatus.OPEN);

      mockLogs.forEach((log, index) => {
        const timeoutId = setTimeout(() => {
          setMessages(prev => [...prev, log]);
        }, (index + 1) * 500);
        timeoutsRef.current.push(timeoutId);
      });

      const closeTimeout = setTimeout(() => {
        setStatus(SseStatus.CLOSED);
      }, (mockLogs.length + 1) * 500);
      timeoutsRef.current.push(closeTimeout);

    }, 300);
    
    timeoutsRef.current.push(connectTimeout);
    
    return () => {
      timeoutsRef.current.forEach(clearTimeout);
    };

  }, [url]);

  return { messages, status };
};
