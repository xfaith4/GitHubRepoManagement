// @vitest-environment jsdom
//
// The rule these tests protect: a portal that is NOT encrypted must say so on a
// surface a signed-in operator actually looks at. The live portal ran degraded
// for 19 days with the warning printed only in a service log and rendered only
// on the login screen, so the two failure directions matter equally — it must
// appear when it should, and it must stay silent when it should, or it becomes
// the chip everyone learns to ignore.
import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import TransportSecurityIndicator, { transportWarning } from './TransportSecurityIndicator';
import type { PortalTransportState } from '../services/apiClient';

afterEach(cleanup);

const degraded: PortalTransportState = {
  scheme: 'http',
  tlsState: 'degraded',
  detail: "TLS is configured ('backend\\config\\tls\\portal.pfx') but the certificate could not be loaded.",
  encryptedInTransit: false,
};

const enabled: PortalTransportState = {
  scheme: 'https',
  tlsState: 'enabled',
  detail: 'Serving HTTPS with certificate portal.pfx.',
  encryptedInTransit: true,
};

const plainLoopback: PortalTransportState = {
  scheme: 'http',
  tlsState: 'disabled',
  detail: 'No certificate configured; serving plain HTTP by design.',
  encryptedInTransit: false,
};

describe('transportWarning', () => {
  it('warns when TLS is configured but unusable — the state that hid for 19 days', () => {
    const w = transportWarning(degraded, true);
    expect(w?.label).toBe('Not encrypted');
    // The host's own sentence, not a reconstructed one.
    expect(w?.detail).toContain('portal.pfx');
  });

  it('warns when an unencrypted portal is reachable off this machine', () => {
    expect(transportWarning(plainLoopback, false)?.label).toBe('Not encrypted (network)');
  });

  it('stays silent for a working HTTPS portal', () => {
    expect(transportWarning(enabled, true)).toBeNull();
    expect(transportWarning(enabled, false)).toBeNull();
  });

  it('stays silent for the documented plain-HTTP loopback default', () => {
    // Not a finding: a loopback bind is not exposed, and a permanent chip here
    // would be the noise that stops the real warnings being read.
    expect(transportWarning(plainLoopback, true)).toBeNull();
  });

  it('stays silent while the transport is still unknown', () => {
    expect(transportWarning(null, true)).toBeNull();
    expect(transportWarning(undefined, undefined)).toBeNull();
  });

  it('does not treat an unknown bind as exposed', () => {
    // isLoopbackBind undefined means "not reported yet". Warning on that would
    // fire on every cold load and train the operator to dismiss it.
    expect(transportWarning(plainLoopback, undefined)).toBeNull();
  });
});

describe('TransportSecurityIndicator', () => {
  it('renders the warning with the host detail as its title', () => {
    render(<TransportSecurityIndicator transport={degraded} isLoopbackBind />);
    const chip = screen.getByTestId('transport-security-warning');
    expect(chip).toHaveTextContent('Not encrypted');
    expect(chip).toHaveAttribute('title', expect.stringContaining('could not be loaded'));
    expect(chip).toHaveAttribute('role', 'status');
  });

  it('renders nothing at all when the transport is sound', () => {
    render(<TransportSecurityIndicator transport={enabled} isLoopbackBind />);
    expect(screen.queryByTestId('transport-security-warning')).not.toBeInTheDocument();
  });
});
