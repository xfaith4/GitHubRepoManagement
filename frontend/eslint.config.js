// ESLint flat config (ROADMAP Lane 0.8). Until 2026-08-10 no linter ran
// anywhere in this repo while Roadmap.Evaluator.ps1 scored OTHER repos on
// their validation signals — this closes the frontend half of that dogfood
// gap. PowerShell gets PSScriptAnalyzer via scripts/Invoke-LintGate.ps1.
import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import reactHooks from 'eslint-plugin-react-hooks';

export default tseslint.config(
  { ignores: ['dist/**', 'node_modules/**'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    plugins: { 'react-hooks': reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
      // `_`-prefixed is the declared "intentionally unused" convention.
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],
      // Debt tier (ROADMAP Lane 0.8), not approval: `warn` + the --max-warnings
      // ratchet in package.json means the count can only shrink. Promote each
      // to 'error' when its count reaches zero.
      //  - no-explicit-any: 123 at baseline (apiClient.ts is the bulk).
      //  - set-state-in-effect: 31 at baseline; each needs individual review
      //    because "fixing" one can change real render behavior.
      '@typescript-eslint/no-explicit-any': 'warn',
      'react-hooks/set-state-in-effect': 'warn',
    },
  },
  {
    // Build plumbing runs under Node, not the browser bundle.
    files: ['**/*.cjs'],
    languageOptions: { sourceType: 'commonjs', globals: globals.node },
  },
  {
    files: ['**/*.mjs', 'vite.config.ts', 'vitest.config.ts'],
    languageOptions: { globals: globals.node },
  }
);
