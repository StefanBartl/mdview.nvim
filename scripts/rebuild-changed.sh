#!/usr/bin/env sh
# Rebuild the local dev artifacts (dist/client, native/server/mdview-server)
# for the files that changed between two revisions:
#
#   scripts/rebuild-changed.sh <from> <to>
#
# Called by the git hooks in .husky/ (after a commit, a merge/pull, a rebase and
# a branch switch), so a dev.web_root / dev.binary_path override never serves a
# stale bundle or relay. Rebuilds only the piece whose sources changed; never
# fails the git operation that called it.

from="$1"
to="${2:-HEAD}"

if [ -z "$from" ] || ! git rev-parse --verify --quiet "$from^{commit}" >/dev/null; then
  # no usable base (a first commit, a fresh clone): compare with the empty tree
  from=$(git hash-object -t tree /dev/null)
fi

changed=$(git diff --name-only "$from" "$to" 2>/dev/null)

rebuild_client=0
rebuild_go=0

echo "$changed" | grep -qE '^(src/client/|native/wasm-render/|package(-lock)?\.json$)' && rebuild_client=1
echo "$changed" | grep -qE '^(native/server/|scripts/build-go\.mjs$)' && rebuild_go=1

# A checkout that never built (or lost) its artifacts gets them regardless.
[ -f dist/client/index.html ] || rebuild_client=1
[ -f native/server/mdview-server ] || [ -f native/server/mdview-server.exe ] || rebuild_go=1

if [ "$rebuild_client" = "1" ]; then
  echo "[rebuild] client/wasm sources changed -> npm run build"
  npm run build || echo "[rebuild] WARNING: client build failed — the dev bundle may be stale"
fi

if [ "$rebuild_go" = "1" ]; then
  echo "[rebuild] relay server sources changed -> npm run build:go"
  npm run build:go || echo "[rebuild] WARNING: relay build failed — the dev binary may be stale (is a session running? :MDView stop)"
fi

if [ "$rebuild_client" = "0" ] && [ "$rebuild_go" = "0" ]; then
  echo "[rebuild] no client/relay source changes — skipping"
fi

exit 0
