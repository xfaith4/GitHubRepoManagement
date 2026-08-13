import React from 'react';
import {
  canApprove,
  canReject,
  countAwaitingDecision,
  describePackagedItemStatus,
  sortPackagedItems,
  type PackagedItem,
} from '../lib/packagedItems';
import {
  resolveDispatchGate,
  type RunnerPresencePayload,
} from '../lib/runnerPresence';

interface PackagedItemQueueProps {
  items: PackagedItem[];
  loading: boolean;
  error: string | null;
  /** Outcome of the last approve/reject, shown until the next action. */
  notice?: string | null;
  /** Packet id currently mid-action, so only that row shows a spinner. */
  busyPacketId: string | null;
  onRefresh: () => void;
  onApprove: (packetId: string) => void;
  onReject: (packetId: string) => void;
  /**
   * Release 3.1 — open this item's trace. Takes whichever id the chain has
   * minted so far; the backend resolves any of them to the same work item.
   */
  onViewTrace: (traceId: string) => void;
  /**
   * Release 3.1 — who, if anyone, can claim what this panel queues. Approving
   * enqueues for the operator runner, so an absent one makes "Approve & queue"
   * a control that writes work nothing will ever pick up.
   */
  runner?: RunnerPresencePayload | null;
}

const SEVERITY_CLASSES: Record<string, string> = {
  pending: 'border-amber-700/50 bg-amber-900/20 text-amber-100',
  ok: 'border-emerald-700/50 bg-emerald-900/20 text-emerald-200',
  error: 'border-red-700/60 bg-red-900/25 text-red-100',
  muted: 'border-slate-700/60 bg-slate-800/40 text-slate-400',
};

const TIER_CLASSES: Record<string, string> = {
  high: 'border-emerald-600/60 text-emerald-200',
  medium: 'border-sky-600/60 text-sky-200',
  low: 'border-slate-600/60 text-slate-300',
  unscored: 'border-slate-700/60 text-slate-400',
};

/**
 * The approval gate, as a surface rather than an API call.
 *
 * A scheduled packaging run ranks each curated repo's pending roadmap work,
 * prices the top item through the budget guard, and stops here. Nothing in this
 * panel merges anything: approving enqueues the packet for the operator runner,
 * which stops at a reviewed branch.
 */
const PackagedItemQueue: React.FC<PackagedItemQueueProps> = ({
  items,
  loading,
  error,
  notice = null,
  busyPacketId,
  onRefresh,
  onApprove,
  onReject,
  onViewTrace,
  runner = null,
}) => {
  const sorted = sortPackagedItems(items);
  const awaiting = countAwaitingDecision(items);
  const gate = resolveDispatchGate(runner);
  const stranded = Number(runner?.strandedCount ?? 0);

  return (
    <section
      data-testid="packaged-item-queue"
      className="mb-4 rounded-lg border border-gray-700 bg-gray-900/50"
    >
      <header className="flex flex-wrap items-center justify-between gap-2 border-b border-gray-700 px-4 py-3">
        <div className="min-w-0">
          <h3 className="text-sm font-semibold text-gray-100">
            Packaged roadmap work
            {awaiting > 0 && (
              <span
                data-testid="packaged-item-pending-count"
                className="ml-2 rounded border border-amber-600/60 bg-amber-900/30 px-1.5 py-0.5 text-[11px] font-semibold text-amber-100"
              >
                {awaiting} awaiting approval
              </span>
            )}
            {/* Release 3.1 — stranded is not the same fact as queued. With a
                runner present this is a queue; without one it is a pile, and
                the operator needs to see which before approving more into it. */}
            {stranded > 0 && (
              <span
                data-testid="packaged-item-stranded-count"
                className="ml-2 rounded border border-red-600/60 bg-red-900/30 px-1.5 py-0.5 text-[11px] font-semibold text-red-100"
                title="Queued with no operator runner able to claim it."
              >
                {stranded} stranded
              </span>
            )}
          </h3>
          <p className="mt-0.5 text-xs text-gray-400">
            Scheduled runs rank each curated repo&apos;s top-value pending item and stop here.
            Approving enqueues it for the operator runner — nothing is pushed or merged.
          </p>
        </div>
        <button
          onClick={onRefresh}
          disabled={loading}
          className="flex-shrink-0 rounded border border-gray-600 px-2.5 py-1 text-xs font-medium text-gray-200 transition-colors hover:bg-gray-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      </header>

      {/* The unmet precondition, in text, above the controls it disables. A
          greyed button with no reason is worse than a failing one: the operator
          cannot tell broken from not-yet-applicable. */}
      {!gate.canQueue && (
        <div
          role="alert"
          data-testid="packaged-item-queue-precondition"
          className="border-b border-amber-800/50 bg-amber-900/20 px-4 py-2 text-xs text-amber-100"
        >
          {gate.unmetPrecondition}
        </div>
      )}

      {error && (
        <div role="alert" data-testid="packaged-item-queue-error" className="border-b border-red-800/50 bg-red-900/20 px-4 py-2 text-xs text-red-200">
          {error}
        </div>
      )}

      {!error && notice && (
        <div role="status" data-testid="packaged-item-queue-notice" className="border-b border-emerald-800/50 bg-emerald-900/20 px-4 py-2 text-xs text-emerald-200">
          {notice}
        </div>
      )}

      {!error && sorted.length === 0 && (
        <p data-testid="packaged-item-queue-empty" className="px-4 py-4 text-xs text-gray-400">
          {loading
            ? 'Loading the approval queue…'
            : 'No packaged items yet. A scheduled packaging run (POST /api/automation/package-run) queues the top-value ready item for each curated L3+ repo.'}
        </p>
      )}

      <ul className="divide-y divide-gray-800">
        {sorted.map(item => {
          const packet = item.packet ?? {};
          const view = describePackagedItemStatus(item.status);
          const busy = busyPacketId === item.packetId;
          const tier = String(packet.valueTier ?? 'unscored');
          return (
            <li key={item.packetId} data-testid="packaged-item-row" data-packet-status={item.status} className="px-4 py-3">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-sm font-medium text-gray-100">{item.repoName || packet.repoName || 'Unknown repo'}</span>
                    <span
                      data-testid="packaged-item-status"
                      className={`rounded border px-1.5 py-0.5 text-[11px] font-semibold ${SEVERITY_CLASSES[view.severity]}`}
                    >
                      {view.label}
                    </span>
                    {packet.maturityLevel && (
                      <span className="rounded border border-gray-600 px-1.5 py-0.5 text-[11px] text-gray-300">
                        {packet.maturityLevel}
                      </span>
                    )}
                  </div>
                  <p className="mt-1 break-words text-sm text-gray-200">{packet.itemText || '(no item text recorded)'}</p>
                  <div className="mt-1.5 flex flex-wrap items-center gap-2 text-[11px] text-gray-400">
                    {/* Every figure here traces to its source: the value score
                        and tier come from the same scorer the dashboard uses,
                        and the work-unit estimate is what the budget guard
                        priced. A badge that cannot be traced is decoration. */}
                    <span className={`rounded border px-1.5 py-0.5 ${TIER_CLASSES[tier] ?? TIER_CLASSES.unscored}`}>
                      value {packet.valueScore ?? 0} · {tier}
                    </span>
                    <span>~{packet.estimatedWorkUnits ?? 0} work units</span>
                    {packet.branch && <code className="rounded bg-gray-800 px-1 py-0.5">{packet.branch}</code>}
                    {item.dispatchRunId && <span>run {item.dispatchRunId}</span>}
                  </div>
                  <p className="mt-1 text-[11px] text-gray-500">{view.detail}</p>
                  {item.note && <p className="mt-1 break-words text-[11px] text-gray-400">{item.note}</p>}
                </div>

                <div className="flex flex-shrink-0 items-center gap-2">
                  {/* Read-only, so it keeps its single click — the bulk-scope
                      rule only requires confirmation for mutating actions. */}
                  <button
                    data-testid="packaged-item-trace"
                    onClick={() => onViewTrace(item.dispatchRunId || item.packetId)}
                    title="Show this item's whole life: rank, prompt, dispatch, run, validation, merge readiness and write-back."
                    className="rounded border border-gray-600 px-2.5 py-1 text-xs font-medium text-gray-200 transition-colors hover:bg-gray-700"
                  >
                    Trace
                  </button>
                  {/* Buttons appear only for transitions the backend accepts,
                      so the UI can never offer an action that 409s. */}
                  {canApprove(item) && (
                    <button
                      data-testid="packaged-item-approve"
                      onClick={() => onApprove(item.packetId)}
                      disabled={busy || !gate.canQueue}
                      title={gate.canQueue
                        ? 'Approve and enqueue for the operator runner. Nothing is pushed or merged.'
                        : gate.unmetPrecondition}
                      className="rounded border border-emerald-600/60 bg-emerald-900/30 px-2.5 py-1 text-xs font-semibold text-emerald-100 transition-colors hover:bg-emerald-800/40 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      {busy ? 'Working…' : 'Approve & queue'}
                    </button>
                  )}
                  {canReject(item) && (
                    <button
                      data-testid="packaged-item-reject"
                      onClick={() => onReject(item.packetId)}
                      disabled={busy}
                      title="Close this packet without dispatching it."
                      className="rounded border border-gray-600 px-2.5 py-1 text-xs font-medium text-gray-200 transition-colors hover:bg-gray-700 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      Reject
                    </button>
                  )}
                </div>
              </div>
            </li>
          );
        })}
      </ul>
    </section>
  );
};

export default PackagedItemQueue;
