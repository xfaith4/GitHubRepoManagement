import { defineConfig } from 'vitest/config';

// Release 2.7 Phase D — frontend unit tests for pure logic. Node environment
// (no DOM needed for these); component/DOM tests can add jsdom later.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['**/*.test.ts'],
    exclude: ['node_modules/**', 'dist/**'],
  },
});
