// Release 3.6 milestone 5 — the leverage family, as the frontend sees it.
//
// The whole contract in one sentence: a metric that could not be derived is
// null WITH a basis, and the UI must render the basis rather than a zero. A
// leverage panel showing "0%" where it means "nobody measured this" would
// argue the product is worthless using a number that does not exist.

export type LeverageUnit = 'percent' | 'count' | 'minutes';

export interface LeverageMetric {
  key: string;
  label: string;
  value: number | null;
  unit: LeverageUnit;
  available: boolean;
  /** Why this figure is what it is — or, when unavailable, what is missing. */
  basis: string;
  sampleSize: number;
}

export interface PortfolioLeverage {
  schemaVersion: string;
  windowDays: number;
  metricCount: number;
  availableCount: number;
  metrics: LeverageMetric[];
}

const asUnit = (value: unknown): LeverageUnit => {
  const text = String(value ?? 'count');
  return text === 'percent' || text === 'minutes' ? text : 'count';
};

export function normalizeLeverageMetric(raw: unknown): LeverageMetric | null {
  if (!raw || typeof raw !== 'object') return null;
  const m = raw as Record<string, unknown>;
  const key = String(m.key ?? '').trim();
  if (!key) return null;
  const available = Boolean(m.available);
  const rawValue = m.value;
  const numeric = rawValue === null || rawValue === undefined || rawValue === '' ? null : Number(rawValue);
  // An unavailable metric never carries a value, whatever the wire said.
  const value = available && numeric !== null && Number.isFinite(numeric) ? numeric : null;
  return {
    key,
    label: String(m.label ?? key),
    value,
    unit: asUnit(m.unit),
    available: available && value !== null,
    basis: String(m.basis ?? ''),
    sampleSize: Number(m.sampleSize ?? 0) || 0,
  };
}

export function normalizePortfolioLeverage(raw: unknown): PortfolioLeverage | null {
  if (!raw || typeof raw !== 'object') return null;
  const l = raw as Record<string, unknown>;
  const metrics = Array.isArray(l.metrics)
    ? l.metrics.map(normalizeLeverageMetric).filter((m): m is LeverageMetric => m !== null)
    : [];
  if (metrics.length === 0) return null;
  return {
    schemaVersion: String(l.schemaVersion ?? 'v1'),
    windowDays: Number(l.windowDays ?? 0) || 0,
    metricCount: Number(l.metricCount ?? metrics.length) || metrics.length,
    availableCount: metrics.filter(m => m.available).length,
    metrics,
  };
}

/** What the tile shows. An unavailable metric shows an em dash, never a zero. */
export function formatLeverageValue(metric: LeverageMetric): string {
  if (!metric.available || metric.value === null) return '—';
  switch (metric.unit) {
    case 'percent':
      return `${Math.round(metric.value * 10) / 10}%`;
    case 'minutes': {
      if (metric.value < 60) return `${Math.round(metric.value * 10) / 10} min`;
      const hours = Math.round((metric.value / 60) * 10) / 10;
      return `${hours} h`;
    }
    default:
      return Math.round(metric.value).toString();
  }
}

/** Metrics the product names but does not yet capture — surfaced, never hidden. */
export function unmeasuredMetrics(leverage: PortfolioLeverage | null): LeverageMetric[] {
  if (!leverage) return [];
  return leverage.metrics.filter(m => !m.available);
}

export function measuredMetrics(leverage: PortfolioLeverage | null): LeverageMetric[] {
  if (!leverage) return [];
  return leverage.metrics.filter(m => m.available);
}
