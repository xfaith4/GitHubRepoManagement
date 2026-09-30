import { describe, it, expect } from 'vitest';
import { describeAssessedAt } from './unattendedReadiness';

// The readiness assessment itself moved to the server with the ranking
// (Release 4.0 phase A); its cases live in tests/Test-OneRanking.ps1.

describe('describeAssessedAt — a fact beside the score, not a warning', () => {
  it('states the age when it is known', () => {
    expect(describeAssessedAt({ indexGeneratedAt: '2026-09-01T00:00:00Z', indexAgeHours: 5 }))
      .toBe('assessed 5 hours ago');
  });

  it('rolls over to days', () => {
    expect(describeAssessedAt({ indexGeneratedAt: '2026-08-20T00:00:00Z', indexAgeHours: 72 }))
      .toBe('assessed 3 days ago');
  });

  it('returns nothing when the time was never recorded, so no column of blanks renders', () => {
    expect(describeAssessedAt(null)).toBeNull();
    expect(describeAssessedAt({ indexGeneratedAt: null, indexAgeHours: null })).toBeNull();
  });
});
