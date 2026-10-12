// Builds the mdview-server relay into native/server/, under the file name the
// running platform can actually execute.
//
// Why this is a script and not a one-liner in package.json: `go build -o NAME`
// takes NAME literally, so the previous `-o mdview-server` wrote an
// extension-less file on Windows. libuv's spawn resolves a command without an
// extension by appending each PATHEXT entry and never tries the bare name, so
// `vim.fn.executable()` said yes and `uv.spawn()` then failed with ENOENT —
// surfacing only as ":MDView start -> failed to start server process". `go env
// GOEXE` is the portable way to ask for the right suffix, and npm runs scripts
// through cmd.exe on Windows, where `$(...)` is not a thing.

import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, renameSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const serverDir = join(dirname(dirname(fileURLToPath(import.meta.url))), 'native', 'server');

/**
 * Run a command in the relay's source directory, inheriting stdio so Go's own
 * diagnostics reach the terminal unchanged.
 * @param {string[]} args
 * @returns {string}
 */
function go(args, capture = false) {
  try {
    return execFileSync('go', args, {
      cwd: serverDir,
      encoding: 'utf8',
      stdio: capture ? ['ignore', 'pipe', 'inherit'] : 'inherit',
    });
  } catch (err) {
    if (err.code === 'ENOENT') {
      console.error('[build:go] Go is not on PATH. Install Go 1.22+ and try again.');
      process.exit(1);
    }
    throw err;
  }
}

// "" on Linux/macOS, ".exe" on Windows.
const goexe = go(['env', 'GOEXE'], true).trim();
const output = `mdview-server${goexe}`;

// Built next to the target and swapped in, not written over it: on Windows a
// running relay (an open :MDView session) keeps its .exe from being replaced,
// but the file can still be renamed out of the way. The session keeps running
// the old build until it is restarted; every start after that gets the new one.
const fresh = `mdview-server.new${goexe}`;
const freshPath = join(serverDir, fresh);
const target = join(serverDir, output);
// A unique name: an earlier build's `.old` may still be the image of a running
// relay, which can be neither deleted nor replaced.
const aside = join(serverDir, `mdview-server.old-${process.pid}-${Date.now()}${goexe}`);
// What a swap leaves behind: exactly these names, nothing a user may have put there.
const leftover = /^mdview-server\.(old-[\d-]+|new)(\.exe)?$/;

/** Delete a file if it can be deleted; a running image or a missing file is fine. */
function tryRemove(path) {
  try {
    rmSync(path, { force: true });
  } catch {
    /* in use by a running relay: the next build sweeps it */
  }
}

// Leftovers of earlier swaps (and of an interrupted build).
for (const name of readdirSync(serverDir)) {
  if (leftover.test(name)) {
    tryRemove(join(serverDir, name));
  }
}

try {
  go(['build', '-o', fresh, '.']);
} catch (err) {
  // Go has already printed its diagnostics; no stack trace on top of them.
  tryRemove(freshPath);
  process.exit(typeof err.status === 'number' ? err.status : 1);
}

let movedAside = false;
if (existsSync(target)) {
  try {
    renameSync(target, aside);
    movedAside = true;
  } catch (err) {
    tryRemove(freshPath);
    console.error(`[build:go] ${target} is in use and cannot be moved: ${err.message}`);
    console.error('[build:go] stop the session (:MDView stop) and build again.');
    process.exit(1);
  }
}

// A scanner or indexer may hold the new file for a moment: a few short retries,
// and if it still does not go in, the old build goes back instead of leaving no
// relay at all.
let swapped = false;
let lastError;
for (let attempt = 0; attempt < 6 && !swapped; attempt++) {
  try {
    renameSync(freshPath, target);
    swapped = true;
  } catch (err) {
    lastError = err;
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100 * (attempt + 1));
  }
}
if (!swapped) {
  if (movedAside) {
    try {
      renameSync(aside, target);
    } catch {
      /* nothing more to do: the message below names the files */
    }
  }
  console.error(`[build:go] could not put ${freshPath} in place: ${lastError?.message}`);
  if (movedAside && existsSync(aside)) {
    console.error(`[build:go] the previous relay is at ${aside} — move it back to ${target}`);
  }
  process.exit(1);
}
if (movedAside) tryRemove(aside);
console.log(`[build:go] ${target}`);

// A build from before this script wrote the extension-less name next door. On
// Windows that file is the one the resolver used to pick and fail on, so a
// rebuild has to take it with it — it is a gitignored artifact of this same
// script, nothing a user put there.
if (goexe !== '') {
  const stale = join(serverDir, 'mdview-server');
  if (existsSync(stale)) {
    rmSync(stale);
    console.log(`[build:go] removed stale extension-less build: ${stale}`);
  }
}
