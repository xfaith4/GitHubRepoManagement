import React from 'react';
import { resolveAutomationStatus, type AutomationHealthPayload } from '../lib/automationStatus';

interface AutomationStatusBadgeProps {
  /** Payload from GET /api/automation/status, or null when unreachable. */
  status: AutomationHealthPayload | null;
  className?: string;
  testId?: string;
  /** Noun the badge labels, so two schedulers do not read identically. */
  subject?: string;
}

const SEVERITY_CLASSES: Record<string, string> = {
  ok: 'border-emerald-700/50 bg-emerald-900/20 text-emerald-200',
  warning: 'border-amber-700/50 bg-amber-900/20 text-amber-100 ring-1 ring-amber-500/40',
  error: 'border-red-700/60 bg-red-900/25 text-red-100 ring-1 ring-red-500/50',
  off: 'border-slate-700/60 bg-slate-800/40 text-slate-400',
  unknown: 'border-slate-700/60 bg-slate-800/40 text-slate-400',
};

const DOT_CLASSES: Record<string, string> = {
  ok: 'bg-emerald-400',
  warning: 'bg-amber-400',
  error: 'bg-red-400',
  off: 'bg-slate-500',
  unknown: 'bg-slate-500',
};

/**
 * Shows whether scheduled automation is actually running.
 *
 * Interval firing is delegated to an external cron, so a scheduler that stops
 * produces no visible change anywhere else in the product — the config keeps
 * reading "enabled" and the run history just stops growing. This badge is the
 * surface that makes that silence visible.
 */
const AutomationStatusBadge: React.FC<AutomationStatusBadgeProps> = ({
  status,
  className = '',
  testId = 'automation-status-badge',
  subject = 'Automation',
}) => {
  const view = resolveAutomationStatus(status, subject);

  return (
    <div
      data-testid={testId}
      data-automation-severity={view.severity}
      data-automation-code={view.code ?? ''}
      role={view.needsAttention ? 'alert' : 'status'}
      title={view.detail}
      className={`inline-flex items-center gap-2 rounded-lg border px-2.5 py-1 text-xs ${SEVERITY_CLASSES[view.severity]} ${className}`}
    >
      <span className={`h-1.5 w-1.5 flex-shrink-0 rounded-full ${DOT_CLASSES[view.severity]}`} aria-hidden="true" />
      <span className="font-semibold">{view.label}</span>
      <span className="hidden sm:inline opacity-80">{view.detail}</span>
    </div>
  );
};

export default AutomationStatusBadge;
