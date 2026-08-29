#!/usr/bin/env bash
# Fixture for the experimental.any_file checklist in TESTS/CHECK.md.
#
# Same purpose as sample.py, in a second language whose comment marker is
# `#`: the shebang on line 1 plus the heading-shaped comments below are what
# a broken filetype gate would collect as an outline.

# Installation
# ## Requirements
# ### Notes

set -euo pipefail

double() {
  echo $(( $1 * 2 ))
}

join() {
  local IFS=", "
  echo "$*"
}

# Padding, so the buffer is taller than one screen.
for i in $(seq 1 30); do
  printf 'line %02d\n' "$i"
done
