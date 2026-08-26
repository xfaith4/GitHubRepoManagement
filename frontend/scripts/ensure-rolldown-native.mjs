// Repairs the one environment defect that breaks `vite build` on a cold
// install: npm's optional-dependency resolution intermittently drops the
// bundler's platform-native binding (npm/cli#4828). Vite 8 bundles with
// Rolldown, whose binding lives in `@rolldown/binding-<platform>-<arch>[-abi]`.
//
// Nothing here is hand-maintained: the candidate list and the exact version
// come from Rolldown's own package.json `optionalDependencies`, so a Rolldown
// upgrade cannot silently strand this script on a stale package name.
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// This package is an npm workspace member; hoisting puts node_modules at the
// repository root, not beside package.json. Walk upward until one is found.
const findInNodeModules = (packageName) => {
  let dir = packageRoot;
  for (;;) {
    const candidate = path.join(dir, 'node_modules', ...packageName.split('/'));
    if (existsSync(candidate)) return candidate;
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
};

const rolldownDir = findInNodeModules('rolldown');
if (!rolldownDir) {
  // No Rolldown at all means dependencies are not installed yet; that is an
  // `npm install` problem, not a binding problem.
  process.exit(0);
}

const rolldownPackage = JSON.parse(readFileSync(path.join(rolldownDir, 'package.json'), 'utf8'));
const optional = rolldownPackage.optionalDependencies ?? {};

const isMusl = () => {
  try {
    return !process.report?.getReport?.().header.glibcVersionRuntime;
  } catch {
    return false;
  }
};

// Narrow Rolldown's binding list to this platform+arch, then disambiguate the
// ABI where more than one exists (linux gnu/musl, android eabi, win32 msvc).
const wanted = `-${process.platform}-${process.arch}`;
const candidates = Object.keys(optional).filter((name) => name.startsWith('@rolldown/binding') && name.includes(wanted));
const preferredAbi = process.platform === 'linux' ? (isMusl() ? 'musl' : 'gnu') : null;
const bindingName =
  candidates.length === 1
    ? candidates[0]
    : (candidates.find((name) => preferredAbi && name.endsWith(`-${preferredAbi}`) || name.endsWith(`-${preferredAbi}eabihf`)) ?? candidates[0] ?? null);

if (!bindingName) {
  // Rolldown ships no native binding for this platform; nothing to repair.
  process.exit(0);
}

if (findInNodeModules(bindingName)) {
  process.exit(0);
}

const version = optional[bindingName];
console.log(`Missing ${bindingName}; installing the Rolldown native binding for ${process.platform}-${process.arch}.`);

// Install beside the hoisted rolldown package so its loader can find it.
const installRoot = path.resolve(rolldownDir, '..', '..');
const npmCommand = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const installResult = spawnSync(
  npmCommand,
  ['install', '--no-save', '--include=optional', `${bindingName}@${version}`],
  { cwd: installRoot, stdio: 'inherit', shell: process.platform === 'win32' }
);

if (installResult.status !== 0) {
  process.exit(installResult.status ?? 1);
}
