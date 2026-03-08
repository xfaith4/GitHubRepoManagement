import { useState, useEffect, useRef } from 'react';

export enum SseStatus {
  CONNECTING = 'CONNECTING',
  OPEN = 'OPEN',
  CLOSED = 'CLOSED',
  ERROR = 'ERROR',
}

export const useSse = (url: string | null) => {
  const [messages, setMessages] = useState<string[]>([]);
  const [status, setStatus] = useState<SseStatus>(SseStatus.CLOSED);
  // Fix: Replaced NodeJS.Timeout with ReturnType<typeof setTimeout> for browser compatibility.
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

    // --- Mock SSE Stream ---
    // This simulates a live log stream for the frontend-only demo.
    // In a real application with a backend, you would replace this with the real EventSource logic.
    
    const startSimulation = () => {
      const operation = url.split('/').pop() || 'operation';
      const mockLogs = [
        `Starting: ${operation}...`,
        `Authenticating with provided credentials... OK`,
        `Locating base path... OK`,
        `Analyzing repositories for ${operation}...`,
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
        setMessages(prev => [...prev, 'Mock connection established...']);

        mockLogs.forEach((log, index) => {
          const timeoutId = setTimeout(() => {
            setMessages(prev => [...prev, log]);
          }, (index + 1) * 600); // Stagger the messages
          timeoutsRef.current.push(timeoutId);
        });

        const closeTimeout = setTimeout(() => {
          setStatus(SseStatus.CLOSED);
          setMessages(prev => [...prev, 'Mock stream finished.']);
        }, (mockLogs.length + 1) * 600);
        timeoutsRef.current.push(closeTimeout);

      }, 500); // Simulate connection delay
      
      timeoutsRef.current.push(connectTimeout);
    };

    startSimulation();
    
    // Cleanup function to run when the component unmounts or the URL changes
    return () => {
      timeoutsRef.current.forEach(clearTimeout);
    };

    /*
    // --- REAL EventSource implementation ---
    // This would be used when connecting to a real backend.
    
    const eventSourceRef = useRef<EventSource | null>(null);
    setMessages([]);
    setStatus(SseStatus.CONNECTING);
    
    const eventSource = new EventSource(url);
    eventSourceRef.current = eventSource;

    eventSource.onopen = () => {
      setStatus(SseStatus.OPEN);
      setMessages(prev => [...prev, 'Connection established...']);
    };

    eventSource.onmessage = (event) => {
      setMessages(prev => [...prev, event.data]);
    };

    eventSource.onerror = () => {
      setStatus(SseStatus.ERROR);
      setMessages(prev => [...prev, 'Connection error. Stream closed.']);
      eventSource.close();
    };

    return () => {
      eventSource.close();
      eventSourceRef.current = null;
    };
    */
    
  }, [url]);

  return { messages, status };
};
