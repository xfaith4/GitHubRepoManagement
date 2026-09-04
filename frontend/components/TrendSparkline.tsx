import React, { useLayoutEffect, useRef, useState } from 'react';
import { buildTrendGeometry, type TrendSeriesPalette } from '../lib/portfolioTrendView';
import type { PortfolioTrendPoint } from '../types';

// The SVG is 96px tall (h-24) and its viewBox is measured-width by 96, so it
// draws at 1:1 and the line spans the card. Before the first measurement the
// fallback keeps the old 320-unit layout, which is what a non-observing
// environment (jsdom) renders.
const HEIGHT = 96;
const PADDING = 10;
const FALLBACK_WIDTH = 320;

interface TrendSparklineProps {
  seriesKey: string;
  points: PortfolioTrendPoint[];
  palette: Pick<TrendSeriesPalette, 'stroke' | 'fill'>;
}

/**
 * A trend series drawn across the full width of its wrapper.
 *
 * The chart used to be a fixed 320-by-92 viewBox in a full-width, fixed-height
 * box. Under the SVG default `preserveAspectRatio` ("meet") the browser scaled
 * it uniformly to the box height and centred it, so on a wide page the line
 * occupied a ~330px strip in the middle of a ~1200px card. Stretching the
 * viewBox instead would distort the stroke and turn the point markers into
 * ellipses; measuring the wrapper and laying the geometry out in real pixels
 * keeps both round.
 */
const TrendSparkline: React.FC<TrendSparklineProps> = ({ seriesKey, points, palette }) => {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(FALLBACK_WIDTH);

  useLayoutEffect(() => {
    const el = wrapperRef.current;
    if (!el) return;
    // A zero width (display:none, a collapsed tab) keeps the last real width
    // rather than collapsing the geometry to a single column.
    const apply = (next: number) => {
      const rounded = Math.round(next);
      if (rounded > 0) setWidth(current => (current === rounded ? current : rounded));
    };
    if (typeof ResizeObserver !== 'undefined') {
      // ResizeObserver reports the current size on observe(), so it is both the
      // first measurement and every later one.
      const observer = new ResizeObserver(entries => {
        for (const entry of entries) apply(entry.contentRect.width);
      });
      observer.observe(el);
      return () => observer.disconnect();
    }
    const frame = requestAnimationFrame(() => apply(el.getBoundingClientRect().width));
    return () => cancelAnimationFrame(frame);
  }, []);

  const geometry = buildTrendGeometry(points, width, HEIGHT, PADDING);
  const baselineY = HEIGHT - PADDING;

  return (
    <div ref={wrapperRef} className="mt-3 w-full" data-testid={`trend-sparkline-${seriesKey}`}>
      <svg viewBox={`0 0 ${width} ${HEIGHT}`} className="block h-24 w-full" aria-hidden="true">
        <line x1={PADDING} y1={baselineY} x2={width - PADDING} y2={baselineY} stroke="rgba(148, 163, 184, 0.18)" strokeWidth="1" />
        <path d={geometry.areaPath} fill={palette.fill} />
        {geometry.coordinates.length > 1 && (
          <polyline
            points={geometry.polyline}
            fill="none"
            stroke={palette.stroke}
            strokeWidth="3"
            strokeLinejoin="round"
            strokeLinecap="round"
          />
        )}
        {geometry.coordinates.map((coord, index) => (
          <circle
            key={`${seriesKey}-${coord.point.date}-${index}`}
            cx={coord.x}
            cy={coord.y}
            r={index === geometry.coordinates.length - 1 ? 4 : 2.5}
            fill={palette.stroke}
            opacity={index === geometry.coordinates.length - 1 ? 1 : 0.6}
          />
        ))}
      </svg>
    </div>
  );
};

export default TrendSparkline;
