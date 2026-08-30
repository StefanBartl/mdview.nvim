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
import { existsSync, rmSync } from 'node:fs';
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

go(['build', '-o', output, '.']);
console.log(`[build:go] ${join(serverDir, output)}`);

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
