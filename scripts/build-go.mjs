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
import { existsSync, renameSync, rmSync } from 'node:fs';
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
const target = join(serverDir, output);
const aside = join(serverDir, `mdview-server.old${goexe}`);

go(['build', '-o', fresh, '.']);
rmSync(aside, { force: true }); // (fails quietly while that old build still runs)
if (existsSync(target)) {
  try {
    renameSync(target, aside);
  } catch (err) {
    rmSync(join(serverDir, fresh), { force: true });
    console.error(`[build:go] ${target} is in use and cannot be moved: ${err.message}`);
    console.error('[build:go] stop the session (:MDView stop) and build again.');
    process.exit(1);
  }
}
renameSync(join(serverDir, fresh), target);
rmSync(aside, { force: true });
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
