
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import ErrorBoundary from './components/ErrorBoundary';
// Inter, self-hosted (MIGRATION.md §4). Latin subset, weights 400 and 500
// only -- §4 caps the design at 500, so shipping 600+ would only add weight
// nobody is allowed to use. ~47KB for both, and no third-party request: this
// console is served over the LAN and has to render with no internet.
import '@fontsource/inter/latin-400.css';
import '@fontsource/inter/latin-500.css';
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
