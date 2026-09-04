// @vitest-environment jsdom
//
// The trend sparkline spans its card.
//
// A fixed 320-unit viewBox under the SVG default `preserveAspectRatio` was
// scaled to the box height and centred, so on a wide page the line sat in a
// ~330px strip in the middle of a ~1200px card. The component now lays the
// geometry out in the wrapper's measured pixel width. These tests drive a
// fake ResizeObserver and assert the viewBox and the end points follow the
// measurement, that a zero-width notification is ignored, and that the
// observer is released on unmount.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, cleanup, act } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import TrendSparkline from './TrendSparkline';
import type { PortfolioTrendPoint } from '../types';

type ResizeCallback = (entries: Array<{ contentRect: { width: number } }>) => void;

const observers: FakeResizeObserver[] = [];

class FakeResizeObserver {
  callback: ResizeCallback;
  observed: Element[] = [];
  disconnected = false;
  constructor(callback: ResizeCallback) {
    this.callback = callback;
    observers.push(this);
  }
  observe(el: Element) { this.observed.push(el); }
  unobserve() { /* unused */ }
  disconnect() { this.disconnected = true; }
  resize(width: number) { this.callback([{ contentRect: { width } }]); }
}

const POINTS: PortfolioTrendPoint[] = [
  { date: '2026-08-01', value: 10 },
  { date: '2026-08-02', value: 30 },
  { date: '2026-08-03', value: 20 },
];

const PALETTE = { stroke: '#34d399', fill: 'rgba(16, 185, 129, 0.18)' };

function renderSparkline() {
  vi.stubGlobal('ResizeObserver', FakeResizeObserver);
  render(<TrendSparkline seriesKey="avgMaturityScore" points={POINTS} palette={PALETTE} />);
  const wrapper = screen.getByTestId('trend-sparkline-avgMaturityScore');
  const svg = wrapper.querySelector('svg') as SVGSVGElement;
  return { wrapper, svg, observer: observers[observers.length - 1] };
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  observers.length = 0;
});

describe('TrendSparkline', () => {
  it('observes its wrapper and lays the geometry out in the measured width', () => {
    const { wrapper, svg, observer } = renderSparkline();
    expect(observer.observed).toContain(wrapper);
    // Before any measurement the fallback keeps the historical layout.
    expect(svg).toHaveAttribute('viewBox', '0 0 320 96');

    act(() => observer.resize(1200));

    expect(svg).toHaveAttribute('viewBox', '0 0 1200 96');
    const circles = svg.querySelectorAll('circle');
    expect(circles).toHaveLength(3);
    expect(circles[0]).toHaveAttribute('cx', '10');
    expect(circles[2]).toHaveAttribute('cx', '1190');
    expect(svg.querySelector('line')).toHaveAttribute('x2', '1190');
    // The peak sits at the top padding, the trough at the baseline.
    expect(circles[1]).toHaveAttribute('cy', '10');
    expect(circles[0]).toHaveAttribute('cy', '86');
  });

  it('keeps the last real width when a resize reports zero', () => {
    const { svg, observer } = renderSparkline();
    act(() => observer.resize(900));
    expect(svg).toHaveAttribute('viewBox', '0 0 900 96');

    act(() => observer.resize(0));
    expect(svg).toHaveAttribute('viewBox', '0 0 900 96');
  });

  it('releases the observer on unmount', () => {
    const { observer } = renderSparkline();
    expect(observer.disconnected).toBe(false);
    cleanup();
    expect(observer.disconnected).toBe(true);
  });
});
