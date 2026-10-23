#!/usr/bin/env node
/**
 * FIST-Mbt MCP launcher — used by both the DSH community package and this
 * repository's local link install.
 *
 * It picks the CLI to run:
 *   1. the newest MoonBit build under `_build/js/*\/build/cmd/cli/cli.js`
 *      (a source checkout that has been built), else
 *   2. the tracked release snapshot `dist/fist-mbt.js` (the published npm
 *      tarball ships exactly that file, so installs need no build step).
 *
 * The child gets its own working directory: a source build runs in the repo
 * (the ledger lives there); a packaged install runs in a per-user data dir so
 * the SQLite ledger has somewhere stable to live.
 *
 * Environment:
 *   FIST_MBT_DATA        packaged-mode data dir (default: ~/.fist-mbt)
 *   FIST_MBT_CWD         force the CLI's working directory
 *   FIST_MBT_AUTO_RELOAD "0" disables the restart-on-new-build watcher
 *   FIST_MBT_NODE        node executable for the CLI (default: this process)
 */
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
// packaging/dsh/ -> package root (the repo root, or node_modules/fist-mbt).
const packageRoot = resolve(here, '..', '..');
const nodeBin = process.env.FIST_MBT_NODE || process.execPath;
const autoReload = process.env.FIST_MBT_AUTO_RELOAD !== '0';

function log(message) {
  // stdout is the JSON-RPC channel: every diagnostic goes to stderr.
  process.stderr.write(`[fist-mbt] ${message}\n`);
}

function fail(message) {
  log(message);
  process.exit(1);
}

// The CLI is a Node 24 build: `node:sqlite` is a hard runtime dependency.
const getBuiltin = typeof process.getBuiltinModule === 'function' ? process.getBuiltinModule.bind(process) : null;
if (getBuiltin === null) fail(`Node >= 24 is required (this is Node ${process.versions.node}).`);
try {
  getBuiltin('node:sqlite');
} catch {
  fail(`This Node (${process.versions.node}) has no node:sqlite. Install Node 24+ and point the DSH host at it.`);
}

/** Every plausible CLI build artifact under `_build/js`, newest first. */
function findBuilds() {
  const found = [];
  const scan = (dir, depth) => {
    if (depth > 8) return;
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) scan(full, depth + 1);
      else if (entry.isFile() && entry.name === 'cli.js' && /[\\/]cmd[\\/]cli[\\/]cli\.js$/.test(full)) {
        try {
          const st = statSync(full);
          found.push({ file: full, mtimeMs: st.mtimeMs, size: st.size });
        } catch {
          /* vanished while scanning */
        }
      }
    }
  };
  scan(join(packageRoot, '_build', 'js'), 0);
  return found.sort((a, b) => b.mtimeMs - a.mtimeMs);
}

const builds = findBuilds();
const release = join(packageRoot, 'dist', 'fist-mbt.js');
const sourceMode = builds.length > 0;
const chosen = sourceMode
  ? { ...builds[0], label: 'source build' }
  : existsSync(release)
    ? { file: release, mtimeMs: statSync(release).mtimeMs, size: statSync(release).size, label: 'release snapshot' }
    : null;

if (chosen === null) {
  fail(
    `no CLI found. Expected a built ${join('_build', 'js', '*', 'build', 'cmd', 'cli', 'cli.js')} ` +
      `or the packaged ${release}. From a source checkout run: moon build --target js cmd/cli`,
  );
}

// A source checkout keeps its ledger in the checkout; a packaged install gets
// a stable per-user directory that the ledger can grow in.
const dataDir = process.env.FIST_MBT_DATA || join(homedir(), '.fist-mbt');
const cwd = process.env.FIST_MBT_CWD || (sourceMode ? packageRoot : dataDir);
try {
  mkdirSync(cwd, { recursive: true });
} catch (error) {
  fail(`cannot create the working directory ${cwd}: ${error.message}`);
}

const startedAt = Date.now();
log(`cli=${chosen.file} (${chosen.label}, ${chosen.size} bytes)`);
log(`cwd=${cwd}`);

// Electron hosts run this script as Node; the child must inherit that mode.
const childEnv = { ...process.env };
if (process.versions.electron !== undefined) childEnv.ELECTRON_RUN_AS_NODE = '1';

const child = spawn(nodeBin, [chosen.file, 'serve'], {
  cwd,
  stdio: 'inherit',
  env: childEnv,
  windowsHide: true,
});

let stopping = false;
const stop = (signal) => {
  if (stopping) return;
  stopping = true;
  try {
    child.kill(signal);
  } catch {
    /* already gone */
  }
};

for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => stop(signal));
}

child.on('error', (error) => fail(`failed to start ${nodeBin}: ${error.message}`));
child.on('exit', (code, signal) => {
  if (stopping) process.exit(0);
  if (signal) log(`CLI exited on ${signal}`);
  process.exit(code ?? 1);
});

// Hot reload: when the selected CLI is replaced (a rebuild, or an npm update
// of the package), drop this connection so the MCP client reconnects to the
// new one. Two stable ticks avoid restarting in the middle of a write.
if (autoReload) {
  let pending = null;
  let pendingTicks = 0;
  const timer = setInterval(() => {
    if (stopping) return;
    const next = sourceMode ? findBuilds()[0] : existsSync(release) ? { file: release, ...statSync(release), mtimeMs: statSync(release).mtimeMs } : null;
    if (!next) return;
    const changed = next.file !== chosen.file || next.mtimeMs > startedAt + 1000;
    if (!changed) {
      pending = null;
      pendingTicks = 0;
      return;
    }
    if (pending && pending.file === next.file && pending.mtimeMs === next.mtimeMs && pending.size === next.size) {
      pendingTicks += 1;
    } else {
      pending = next;
      pendingTicks = 0;
      return;
    }
    if (pendingTicks >= 2) {
      clearInterval(timer);
      log(`new CLI detected: ${next.file} — restarting so DSH picks it up`);
      stop('SIGTERM');
      setTimeout(() => process.exit(0), 3000).unref();
    }
  }, 3000);
  timer.unref();
}
