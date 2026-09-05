import React, { useEffect, useState } from 'react';
import { getPortalVersion } from '../services/apiClient';
import { resolveBuildStamp, type PortalVersionPayload } from '../lib/buildStamp';

/**
 * Header chip naming the code you are looking at.
 *
 * Asked for directly by the operator: after a change lands, there was no way
 * to confirm the portal in the browser was the updated one. Two stamps rather
 * than one, because they move independently — `frontend/dist` is served
 * per-request so a rebuild is live immediately, while the API host only
 * changes when the service restarts.
 *
 * Deliberately quiet. A drifted host is stated as fact in the chip, not
 * raised as a banner: landing surfaces do not open with an alarm, and a
 * restart-pending host is a normal state during a deploy, not a fault.
 */
const POLL_MS = 60_000;

function BuildStampIndicator() {
  const [api, setApi] = useState<PortalVersionPayload | null>(null);

  useEffect(() => {
    let cancelled = false;
    const poll = async () => {
      const data = await getPortalVersion();
      if (!cancelled) setApi(data);
    };
    void poll();
    const timer = setInterval(poll, POLL_MS);
    return () => { cancelled = true; clearInterval(timer); };
  }, []);

  const view = resolveBuildStamp(
    typeof __BUILD_COMMIT__ === 'string' ? __BUILD_COMMIT__ : null,
    typeof __BUILD_TIME__ === 'string' ? __BUILD_TIME__ : '',
    api,
  );

  return (
    <span
      data-testid="build-stamp"
      data-state={view.state}
      title={view.detail}
      className={
        'inline-flex items-center gap-1 rounded border px-1.5 py-0.5 font-mono text-xs ' +
        (view.drifted
          ? 'border-amber-500/40 bg-amber-500/10 text-amber-300'
          : 'border-text/10 bg-text/5 text-text/55')
      }
    >
      {view.label}
    </span>
  );
}

export default BuildStampIndicator;
