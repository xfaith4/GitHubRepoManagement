import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(scriptDir, '..');
const requireFromPackage = (specifier) => {
  const modulePath = path.join(packageRoot, 'node_modules', ...specifier.split('/'));
  return modulePath;
};

const isMusl = () => {
  try {
    return !process.report?.getReport?.().header.glibcVersionRuntime;
  } catch {
    return false;
  }
};

const getRollupPackageBase = () => {
  const bindings = {
    android: {
      arm: 'android-arm-eabi',
      arm64: 'android-arm64',
    },
    darwin: {
      arm64: 'darwin-arm64',
      x64: 'darwin-x64',
    },
    freebsd: {
      arm64: 'freebsd-arm64',
      x64: 'freebsd-x64',
    },
    linux: {
      arm: isMusl() ? 'linux-arm-musleabihf' : 'linux-arm-gnueabihf',
      arm64: isMusl() ? 'linux-arm64-musl' : 'linux-arm64-gnu',
      loong64: 'linux-loong64-gnu',
      ppc64: 'linux-ppc64-gnu',
      riscv64: isMusl() ? 'linux-riscv64-musl' : 'linux-riscv64-gnu',
      s390x: 'linux-s390x-gnu',
      x64: isMusl() ? 'linux-x64-musl' : 'linux-x64-gnu',
    },
    openharmony: {
      arm64: 'openharmony-arm64',
    },
    win32: {
      arm64: 'win32-arm64-msvc',
      ia32: 'win32-ia32-msvc',
      x64: process.env.MSYSTEM ? 'win32-x64-gnu' : 'win32-x64-msvc',
    },
  };

  return bindings[process.platform]?.[process.arch] ?? null;
};

const rollupPackageJsonPath = path.join(packageRoot, 'node_modules', 'rollup', 'package.json');
if (!existsSync(rollupPackageJsonPath)) {
  process.exit(0);
}

const rollupPackage = JSON.parse(readFileSync(rollupPackageJsonPath, 'utf8'));
const packageBase = getRollupPackageBase();
if (!packageBase) {
  process.exit(0);
}

const expectedPackageName = `@rollup/rollup-${packageBase}`;
const expectedPackagePath = requireFromPackage(expectedPackageName);
const bundledBinaryPath = path.join(packageRoot, 'node_modules', 'rollup', 'dist', `rollup.${packageBase}.node`);

if (existsSync(expectedPackagePath) || existsSync(bundledBinaryPath)) {
  process.exit(0);
}

console.log(`Missing ${expectedPackageName}; installing Rollup native binary for ${process.platform}-${process.arch}.`);

const npmCommand = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const installResult = spawnSync(
  npmCommand,
  ['install', '--no-save', '--include=optional', `${expectedPackageName}@${rollupPackage.version}`],
  {
    cwd: packageRoot,
    stdio: 'inherit',
  }
);

if (installResult.status !== 0) {
  process.exit(installResult.status ?? 1);
}
