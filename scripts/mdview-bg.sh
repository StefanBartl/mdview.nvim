#!/usr/bin/env sh
# mdview-bg — open a Markdown file in a standalone mdview preview from the
# terminal, with no long-lived Neovim in the chain.
#
#   mdview-bg README.md               # preview in the browser
#   mdview-bg --no-browser notes.md   # start the relay only, print its URL
#
# It runs a throwaway headless Neovim just long enough to launch `:MDView
# standalone` — which spawns the relay watching the file on disk and detaches
# it — then quits. The relay keeps running independently, following the file,
# until you kill it or close the preview. Nothing here stays resident.
#
# `nvim +MDView --background file.md` is NOT valid Neovim syntax (`+cmd` takes
# no trailing flags); this script is the supported spelling of that idea.
#
# Standalone needs a relay binary with --watch support (v0.3.0+). Until a
# release ships, point $MDVIEW_STANDALONE_BIN at a locally built one:
#   MDVIEW_STANDALONE_BIN=~/repos/mdview.nvim/native/server/mdview-server
#
# Environment:
#   MDVIEW_PATH             mdview.nvim checkout (default: derived from this script)
#   LIB_NVIM_PATH           lib.nvim checkout, if not next to mdview.nvim
#   MDVIEW_STANDALONE_BIN   relay binary override (see above)
#   NVIM                    nvim binary to use (default: nvim on PATH)

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
: "${MDVIEW_PATH:=$(dirname -- "$SCRIPT_DIR")}"
: "${NVIM:=nvim}"
export MDVIEW_PATH

FILE=''
NO_BROWSER=0

usage() {
	sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

while [ $# -gt 0 ]; do
	case "$1" in
		--no-browser) NO_BROWSER=1 ;;
		-h|--help) usage 0 ;;
		-*) printf 'mdview-bg: unknown option: %s\n' "$1" >&2; usage 1 ;;
		*)
			if [ -n "$FILE" ]; then
				printf 'mdview-bg: more than one file given\n' >&2
				exit 1
			fi
			FILE=$1
			;;
	esac
	shift
done

if [ -z "$FILE" ]; then
	printf 'mdview-bg: no file given\n' >&2
	usage 1
fi
if [ ! -r "$FILE" ]; then
	printf 'mdview-bg: not a readable file: %s\n' "$FILE" >&2
	exit 1
fi
if ! command -v "$NVIM" >/dev/null 2>&1; then
	printf 'mdview-bg: %s not found on PATH (set $NVIM to override)\n' "$NVIM" >&2
	exit 1
fi

INIT="$MDVIEW_PATH/scripts/minimal_init.lua"
if [ ! -r "$INIT" ]; then
	printf 'mdview-bg: minimal init not found at %s\n' "$INIT" >&2
	printf '           set $MDVIEW_PATH to your mdview.nvim checkout\n' >&2
	exit 1
fi

# Absolute path: the relay resolves its room key from it, and its cwd differs
# from this shell's.
FILE=$(CDPATH='' cd -- "$(dirname -- "$FILE")" && printf '%s/%s' "$(pwd)" "$(basename -- "$FILE")")

CMD="MDView standalone $FILE"
[ "$NO_BROWSER" -eq 1 ] && CMD="$CMD --no-browser"

# The Neovim launcher is short-lived (it spawns the detached relay and quits),
# so it can run in the foreground — its output carries the standalone
# notification, incl. the preview URL under --no-browser.
exec "$NVIM" --headless -u "$INIT" -c "$CMD" -c "qa!"
