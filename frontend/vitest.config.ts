import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

// Release 2.7 Phase D — frontend unit tests for pure logic (node environment).
// ROADMAP Lane 0.8 added component/DOM tests: *.test.tsx files run under jsdom
// via a per-file `// @vitest-environment jsdom` pragma, so the pure-logic
// tests keep the cheaper node environment.
export default defineConfig({
  plugins: [react()],
  // vite.config.ts injects these at build time; tests need them defined too,
  // or the version chip renders its "built outside a checkout" branch and the
  // match/mismatch cases can never be exercised.
  define: {
    __BUILD_COMMIT__: JSON.stringify('testsha'),
    __BUILD_TIME__: JSON.stringify('2026-09-05T12:00:00.000Z'),
  },
  test: {
    environment: 'node',
    include: ['**/*.test.ts', '**/*.test.tsx'],
    exclude: ['node_modules/**', 'dist/**'],
  },
});
