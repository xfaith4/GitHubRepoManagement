import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

// Release 2.7 Phase D — frontend unit tests for pure logic (node environment).
// ROADMAP Lane 0.8 added component/DOM tests: *.test.tsx files run under jsdom
// via a per-file `// @vitest-environment jsdom` pragma, so the pure-logic
// tests keep the cheaper node environment.
export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'node',
    include: ['**/*.test.ts', '**/*.test.tsx'],
    exclude: ['node_modules/**', 'dist/**'],
  },
});
