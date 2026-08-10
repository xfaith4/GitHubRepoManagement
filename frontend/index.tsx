
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import ErrorBoundary from './components/ErrorBoundary';
import './styles.css';

const rootElement = document.getElementById('root');
if (!rootElement) {
  throw new Error("Could not find root element to mount to");
}

const root = ReactDOM.createRoot(rootElement);
root.render(
  <React.StrictMode>
    {/* Last-resort boundary: an unhandled render error shows a named card
        instead of a silent white screen (frontend hardening, 2026-08-10). */}
    <ErrorBoundary label="The portal">
      <App />
    </ErrorBoundary>
  </React.StrictMode>
);
