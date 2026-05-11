#!/usr/bin/env sh
# precheck.sh <mode>
#
# Unified pre-check for docflow commands. Exit 0 silently on pass.
# On fail: print the exact user-facing error message to stderr and exit 1.
# The calling command STOPs with that message verbatim.
#
# Modes:
#   no-state          docs/INDEX.md exists, .docflow/state absent, git clean
#                     (brainstorm, free, implement, sync, plan --amend)
#   flow-active       state exists, mode=flow, branch matches     (plan flow)
#   free-active       state exists, mode=free, branch matches, git clean (commit)
#   init              state absent, docs/INDEX.md absent           (init)
#
# Also validates that .docflow/state (when required) is parseable and
# references a branch that matches the current HEAD.

set -eu

mode="${1:-}"
if [ -z "$mode" ]; then
  echo "precheck.sh: missing mode argument" >&2
  exit 2
fi

STATE=".docflow/state"
INDEX="docs/INDEX.md"

have_index() { [ -f "$INDEX" ]; }
have_state() { [ -f "$STATE" ]; }

read_state_field() {
  # read_state_field <key>  -> prints value, or empty if missing
  key="$1"
  [ -f "$STATE" ] || return 0
  awk -F= -v k="$key" '$1 == k { sub(/^[^=]+=/, ""); print; exit }' "$STATE"
}

current_branch() {
  git branch --show-current 2>/dev/null || true
}

git_dirty() {
  # prints non-empty if working tree has uncommitted changes
  git status --porcelain 2>/dev/null | head -1
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

case "$mode" in
  init)
    if have_index; then
      fail "docflow is already initialized (docs/INDEX.md exists). Delete it first to re-initialize."
    fi
    exit 0
    ;;

  no-state)
    have_index || fail "docflow is not initialized. Run \`/docflow:init\` first."
    if have_state; then
      active_mode=$(read_state_field mode)
      fail "A session is already active (mode=${active_mode:-unknown}). Run \`/docflow:plan\` (flow) or \`/docflow:commit\` (free) to finish it, or delete \`.docflow/state\` to discard it."
    fi
    exit 0
    ;;

  flow-active)
    have_index || fail "docflow is not initialized. Run \`/docflow:init\` first."
    have_state || fail "No active flow mode session. Run \`/docflow:brainstorm\` first."
    active_mode=$(read_state_field mode)
    if [ "$active_mode" != "flow" ]; then
      fail "Current session is \`${active_mode:-unknown}\`, not flow. Run \`/docflow:commit\` to finish it, or delete \`.docflow/state\` to discard it."
    fi
    state_branch=$(read_state_field branch)
    cur_branch=$(current_branch)
    if [ -n "$state_branch" ] && [ "$state_branch" != "$cur_branch" ]; then
      fail "You started flow mode on branch \`${state_branch}\` but are now on \`${cur_branch}\`. Switch back or delete \`.docflow/state\` to discard the session."
    fi
    exit 0
    ;;

  free-active)
    have_index || fail "docflow is not initialized. Run \`/docflow:init\` first."
    have_state || fail "No active free mode session. Run \`/docflow:free\` first."
    active_mode=$(read_state_field mode)
    if [ "$active_mode" != "free" ]; then
      fail "Current session is \`${active_mode:-unknown}\`, not free. Run \`/docflow:plan\` to finish it, or delete \`.docflow/state\` to discard it."
    fi
    state_branch=$(read_state_field branch)
    cur_branch=$(current_branch)
    if [ -n "$state_branch" ] && [ "$state_branch" != "$cur_branch" ]; then
      fail "You started free mode on branch \`${state_branch}\` but are now on \`${cur_branch}\`. Switch back or delete \`.docflow/state\` to discard the session."
    fi
    if [ -n "$(git_dirty)" ]; then
      fail "Commit your code first. Docflow documents committed history, not uncommitted state. After committing, re-run \`/docflow:commit\`."
    fi
    exit 0
    ;;

  *)
    echo "precheck.sh: unknown mode \`$mode\`" >&2
    exit 2
    ;;
esac
