// @vitest-environment jsdom
//
// Release 3.6 milestone 5 — the leverage panel.
//
// The failure this prevents: a scorecard that renders "0%" where it means
// "nobody measured this", arguing the product is worthless with a number that
// does not exist. An unmeasured figure must show an em dash and say why.
import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, within, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import LeveragePanel from './LeveragePanel';
import { normalizePortfolioLeverage } from '../lib/portfolioLeverage';

afterEach(() => cleanup());

const leverage = () =>
  normalizePortfolioLeverage({
    schemaVersion: 'v1',
    windowDays: 30,
    metrics: [
      { key: 'agentFirstPassSuccess', label: 'Agent first-pass success', value: 50, unit: 'percent', available: true, basis: '1 of 2 completed agent run(s) needed no retry.', sampleSize: 2 },
      { key: 'repositoriesNeedingNothing', label: 'Repositories needing nothing', value: 12, unit: 'count', available: true, basis: '12 of 34 repositories concluded appropriate as-is.', sampleSize: 34 },
      { key: 'operatorMinutesPerTask', label: 'Operator minutes per task', value: null, unit: 'minutes', available: false, basis: 'Not captured: the product records agent elapsed time, never the operator\'s own minutes.', sampleSize: 0 },
      { key: 'recommendationsAccepted', label: 'Recommendations accepted vs rejected', value: null, unit: 'percent', available: false, basis: 'Not captured: approving a packaged item leaves no accept/reject ledger.', sampleSize: 0 },
    ],
  });

describe('LeveragePanel — every figure names its ledger', () => {
  it('renders each measured metric with its value and its basis', () => {
    render(<LeveragePanel leverage={leverage()} />);
    const measured = screen.getByTestId('leverage-measured');
    expect(within(measured).getByText('50%')).toBeInTheDocument();
    expect(within(measured).getByText('12')).toBeInTheDocument();
    expect(within(measured).getByText('1 of 2 completed agent run(s) needed no retry.')).toBeInTheDocument();
    expect(within(measured).getByText('n = 34')).toBeInTheDocument();
  });

  it('names the window the figures cover', () => {
    render(<LeveragePanel leverage={leverage()} />);
    expect(screen.getByText(/over the last 30 days/)).toBeInTheDocument();
  });
});

describe('LeveragePanel — what the product does not capture is stated, not omitted', () => {
  it('lists the unmeasured metrics with the reason each is missing', () => {
    render(<LeveragePanel leverage={leverage()} />);
    const unmeasured = screen.getByTestId('leverage-unmeasured');
    expect(within(unmeasured).getByText('Operator minutes per task')).toBeInTheDocument();
    expect(within(unmeasured).getByText(/never the operator's own minutes/)).toBeInTheDocument();
    expect(within(unmeasured).getByText(/no accept\/reject ledger/)).toBeInTheDocument();
    expect(within(unmeasured).getByText(/a gap in the product, not evidence of nothing/)).toBeInTheDocument();
  });

  it('never renders a zero for an unmeasured metric', () => {
    render(<LeveragePanel leverage={leverage()} />);
    const unmeasured = screen.getByTestId('leverage-unmeasured');
    expect(within(unmeasured).queryByText('0')).not.toBeInTheDocument();
    expect(within(unmeasured).queryByText('0%')).not.toBeInTheDocument();
    // The measured half must not have picked them up either.
    const measured = screen.getByTestId('leverage-measured');
    expect(within(measured).queryByText('Operator minutes per task')).not.toBeInTheDocument();
  });

  it('says leverage was not computed rather than showing an empty scorecard', () => {
    render(<LeveragePanel leverage={null} />);
    expect(screen.getByTestId('leverage-absent')).toHaveTextContent(/derived from the agent-run, execution, and verification ledgers/);
    expect(screen.queryByTestId('leverage-measured')).not.toBeInTheDocument();
  });
});
