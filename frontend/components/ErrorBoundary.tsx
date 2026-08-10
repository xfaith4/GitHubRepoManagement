import React from 'react';

// React error boundary (frontend hardening, 2026-08-10). Until this existed,
// a render-time throw in ANY of the ~38 components white-screened the whole
// portal — no message, no recovery, and the operator's only move was a hard
// reload. A class component is not legacy style here: componentDidCatch /
// getDerivedStateFromError have no hook equivalent.
//
// Two mount points:
//  - index.tsx wraps <App /> — the last-resort full-page card.
//  - Dashboard wraps the active tab panel with key={activeView}, so a crashed
//    view degrades to a named error card while the header, tab strip, and the
//    other five views keep working — and switching tabs resets the boundary.

interface ErrorBoundaryProps {
  /** Names the failed region in the error card ("The portal", a view label…). */
  label: string;
  children: React.ReactNode;
}

interface ErrorBoundaryState {
  error: Error | null;
}

class ErrorBoundary extends React.Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { error: null };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo): void {
    // The card shows the message; the console keeps the component stack.
    console.error(`[ErrorBoundary] ${this.props.label} crashed:`, error, info.componentStack);
  }

  private handleReset = (): void => {
    this.setState({ error: null });
  };

  render(): React.ReactNode {
    if (this.state.error) {
      return (
        <div
          role="alert"
          data-testid="error-boundary-card"
          className="m-4 rounded-lg border border-red-700/50 bg-red-900/20 px-5 py-4"
        >
          <h2 className="text-base font-semibold text-red-200">
            {this.props.label} hit an error and could not render
          </h2>
          <p className="mt-2 text-sm text-red-100/90 break-words">
            {this.state.error.message || String(this.state.error)}
          </p>
          <p className="mt-2 text-xs text-red-200/70">
            The rest of the portal keeps working. Try again below; if it
            recurs, the browser console has the component stack.
          </p>
          <button
            onClick={this.handleReset}
            className="mt-3 px-3 py-1.5 rounded border border-red-600/60 bg-red-900/40 text-sm text-red-100 hover:bg-red-900/60 transition-colors"
          >
            Try again
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

export default ErrorBoundary;
