#!/usr/bin/env sh
# mdview-bg — open a Markdown file in an mdview preview from the terminal,
# without tying the preview to the shell that started it.
#
#   mdview-bg README.md               # preview in the browser, return the prompt
#   mdview-bg --no-browser notes.md   # start the relay only, print nothing to open
#   mdview-bg --fg docs/spec.md       # stay in the foreground (Ctrl-C to stop)
#
# It runs Neovim headless against scripts/minimal_init.lua, so the preview gets
# the full plugin (live push, scroll sync) while loading none of your own
# config — a background process shouldn't depend on, or keep alive, plugins
# that have nothing to do with the preview.
#
# `nvim +MDView --background file.md` is NOT valid Neovim syntax (`+cmd` takes
# no trailing flags); this script is the supported spelling of that idea.
#
# Environment:
#   MDVIEW_PATH     mdview.nvim checkout (default: derived from this script)
#   LIB_NVIM_PATH   lib.nvim checkout, if not next to mdview.nvim
#   NVIM            nvim binary to use (default: nvim on PATH)

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
: "${MDVIEW_PATH:=$(dirname -- "$SCRIPT_DIR")}"
: "${NVIM:=nvim}"
export MDVIEW_PATH

FOREGROUND=0
FILE=''

usage() {
	sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

while [ $# -gt 0 ]; do
	case "$1" in
		--no-browser) MDVIEW_NO_BROWSER=1; export MDVIEW_NO_BROWSER ;;
		--fg|--foreground) FOREGROUND=1 ;;
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

# Absolute path: the detached process may not share this shell's cwd.
FILE=$(CDPATH='' cd -- "$(dirname -- "$FILE")" && printf '%s/%s' "$(pwd)" "$(basename -- "$FILE")")

if [ "$FOREGROUND" -eq 1 ]; then
	exec "$NVIM" --headless -u "$INIT" -c 'MDView start' "$FILE"
fi

# setsid where available so the preview survives the terminal closing, not just
# the shell exiting; plain nohup elsewhere (macOS has no setsid).
if command -v setsid >/dev/null 2>&1; then
	setsid "$NVIM" --headless -u "$INIT" -c 'MDView start' "$FILE" \
		>/dev/null 2>&1 < /dev/null &
else
	nohup "$NVIM" --headless -u "$INIT" -c 'MDView start' "$FILE" \
		>/dev/null 2>&1 < /dev/null &
fi

printf 'mdview: previewing %s in the background (pid %s)\n' "$(basename -- "$FILE")" "$!"
printf 'mdview: close the preview tab to stop it, or: kill %s\n' "$!"
