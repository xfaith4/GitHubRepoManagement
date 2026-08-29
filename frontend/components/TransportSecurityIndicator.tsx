/**
 * "This connection is not encrypted", on every authenticated screen.
 *
 * WHY THIS EXISTS. The host has reported its real transport state on every
 * payload since Release 3.3 — `tlsState: 'degraded'` meaning TLS was configured
 * and could not be used, so the portal is plain HTTP while its config claims
 * otherwise. The frontend rendered that in exactly one place: the login screen.
 *
 * An operator who is already signed in — which is every operator, most of the
 * time — was never told. That is how this portal ran with a broken certificate
 * from 2026-08-10 to 2026-08-29, with `WARN TLS: DEGRADED — credentials typed
 * into this portal are not encrypted in transit` printed on every single service
 * start, and nobody looking at a log. A warning only the log carries is a
 * warning the product does not make.
 *
 * TWO STATES ARE WORTH INTERRUPTING FOR, and they are different harms:
 *
 *   degraded            — config claims TLS, the connection has none. The
 *                         operator believes they are encrypted and are not.
 *   unencrypted on LAN  — no TLS configured AND the host is not on loopback,
 *                         so credentials cross the network in clear text. This
 *                         is the shared-LAN path (Release 2.9) without a
 *                         certificate.
 *
 * Everything else renders nothing. A plain-HTTP loopback bind is the documented
 * default and a permanent chip saying so would be noise — and a chip nobody
 * needs is how the ones that matter stop being read.
 */
import type { PortalTransportState } from '../services/apiClient';

interface TransportSecurityIndicatorProps {
  transport?: PortalTransportState | null;
  /** Loopback binds are not exposed, so an unencrypted one is not a finding. */
  isLoopbackBind?: boolean;
}

export interface TransportWarning {
  label: string;
  detail: string;
}

/**
 * Pure: the warning this transport deserves, or null. Exported so the rule can
 * be tested without a DOM, and so the same rule can be reused if another
 * surface needs it.
 */
export function transportWarning(
  transport: PortalTransportState | null | undefined,
  isLoopbackBind: boolean | undefined,
): TransportWarning | null {
  if (!transport) return null;

  if (transport.tlsState === 'degraded') {
    return {
      label: 'Not encrypted',
      // The host's own sentence, which names the certificate and the reason.
      // Never reconstructed here: a second opinion about why TLS failed is how
      // two surfaces come to disagree about one fact.
      detail: transport.detail || 'TLS is configured but unavailable; this connection is plain HTTP.',
    };
  }

  if (!transport.encryptedInTransit && isLoopbackBind === false) {
    return {
      label: 'Not encrypted (network)',
      detail:
        transport.detail ||
        'This portal is reachable off this machine and has no TLS certificate, so credentials cross the network in clear text.',
    };
  }

  return null;
}

const TransportSecurityIndicator = ({ transport, isLoopbackBind }: TransportSecurityIndicatorProps) => {
  const warning = transportWarning(transport, isLoopbackBind);
  if (!warning) return null;

  return (
    <span
      role="status"
      data-testid="transport-security-warning"
      title={warning.detail}
      className="inline-flex items-center gap-1.5 rounded border border-amber-600/60 bg-amber-900/30 px-2 py-0.5 text-[13px] font-medium text-amber-200"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        className="h-3.5 w-3.5 flex-shrink-0"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <rect x="3" y="11" width="18" height="11" rx="2" />
        <path d="M7 11V7a5 5 0 0 1 9.9-1" />
      </svg>
      {warning.label}
    </span>
  );
};

export default TransportSecurityIndicator;
