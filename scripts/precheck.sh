#!/usr/bin/env sh
# precheck.sh <mode>
#
# Unified pre-check for specflow commands. Exit 0 silently on pass.
# On fail: print the exact user-facing error message to stderr and exit 1.
# The calling command STOPs with that message verbatim.
#
# Modes:
#   init           specs/INDEX must NOT exist (for /specflow:init)
#   initialized    specs/INDEX must exist     (for /specflow:spec, implement, sync)

set -eu

mode="${1:-}"
if [ -z "$mode" ]; then
  echo "precheck.sh: missing mode argument" >&2
  exit 2
fi

INDEX="specs/INDEX"

# Operate from the repo root (worktree root when inside a worktree) so the
# relative specs/INDEX check is correct regardless of the caller's CWD. Without
# this, running a command from a subdirectory misreports the init state.
root=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$root" ] && cd "$root"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

case "$mode" in
  init)
    if [ -f "$INDEX" ]; then
      fail "specflow is already initialized (specs/INDEX exists). Delete it first to re-initialize."
    fi
    exit 0
    ;;

  initialized)
    [ -f "$INDEX" ] || fail "specflow is not initialized. Run \`/specflow:init\` first."
    exit 0
    ;;

  *)
    echo "precheck.sh: unknown mode \`$mode\`" >&2
    exit 2
    ;;
esac
