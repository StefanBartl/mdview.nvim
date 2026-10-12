#!/usr/bin/env sh
# Rebuild the local dev artifacts (dist/client, native/server/mdview-server)
# for the files that changed between two revisions:
#
#   scripts/rebuild-changed.sh <from> <to> [norebase]
#
# Called by the git hooks in .husky/ (after a commit, a merge/pull, a rebase and
# a branch switch), so a dev.web_root / dev.binary_path override never serves a
# stale bundle or relay. Rebuilds only the piece whose sources changed; never
# fails the git operation that called it.
#
#   norebase   do nothing while a rebase is running: it replays every commit
#              through post-commit, and post-rewrite builds once at the end.
#   checkout   the same for a checkout, except when the rebase has nothing left
#              to replay (then no post-rewrite follows).
#
# MDVIEW_NO_REBUILD=1 switches it off.

[ "$MDVIEW_NO_REBUILD" = "1" ] && exit 0

# Always from the top of the checkout the hook ran in (the paths below are
# relative to it), also when started by hand from a subfolder.
cd "$(git rev-parse --show-toplevel)" || exit 0

case "$3" in
  norebase)
    for d in rebase-merge rebase-apply; do
      [ -d "$(git rev-parse --git-path "$d")" ] && exit 0
    done
    ;;
  checkout)
    # The checkout a rebase starts with (onto the new base) is followed by
    # post-rewrite; one that has nothing left to replay (a fast-forward rebase)
    # is not, so that one builds here.
    if [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
      exit 0
    fi
    todo="$(git rev-parse --git-path rebase-merge)/git-rebase-todo"
    if [ -d "$(git rev-parse --git-path rebase-merge)" ] && grep -qE '^[a-z]' "$todo" 2>/dev/null; then
      exit 0
    fi
    ;;
esac

from="$1"
to="${2:-HEAD}"

if [ -z "$from" ] || ! git rev-parse --verify --quiet "$from^{commit}" >/dev/null; then
  # no usable base (a first commit, a new worktree, a fresh clone): compare with
  # the empty tree
  from=$(git hash-object -t tree /dev/null)
fi

# --no-renames: a file moved out of src/client/ shows up as deleted there too.
changed=$(git -c core.quotepath=off diff --no-renames --name-only "$from" "$to" 2>/dev/null)

rebuild_client=0
rebuild_go=0

echo "$changed" | grep -qE '^(src/client/|native/wasm-render/|package(-lock)?\.json$)' && rebuild_client=1
echo "$changed" | grep -qE '^(native/server/|scripts/build-go\.mjs$)' && rebuild_go=1

# A checkout that never built (or lost) its artifacts gets them regardless --
# but only where the tools for it exist, so a new worktree without
# node_modules is not sent into a cold Rust build on every git command.
[ -f dist/client/index.html ] || rebuild_client=1
[ -f native/server/mdview-server ] || [ -f native/server/mdview-server.exe ] || rebuild_go=1

if [ "$rebuild_client" = "1" ]; then
  # vite in node_modules/.bin: a bare node_modules folder (a cache that vitest
  # or vite created) does not mean the dependencies are installed.
  if [ -e node_modules/.bin/vite ] && command -v wasm-pack >/dev/null 2>&1; then
    echo "[rebuild] client/wasm sources changed or dist/client is missing -> npm run build"
    npm run build || echo "[rebuild] WARNING: client build failed — the dev bundle may be stale"
  else
    echo "[rebuild] dist/client is out of date, but the dependencies or wasm-pack are missing — skipped (npm ci; see docs/development.md)"
    rebuild_client=0
  fi
fi

if [ "$rebuild_go" = "1" ]; then
  if command -v go >/dev/null 2>&1; then
    echo "[rebuild] relay server sources changed -> npm run build:go"
    npm run build:go || echo "[rebuild] WARNING: relay build failed — the dev binary may be stale (is a session running? :MDView stop)"
  else
    echo "[rebuild] the relay is out of date or missing, but Go is not on PATH — skipped"
    rebuild_go=0
  fi
fi

if [ "$rebuild_client" = "0" ] && [ "$rebuild_go" = "0" ]; then
  echo "[rebuild] nothing to rebuild"
fi

exit 0
