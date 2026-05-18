---
description: Implement a single spec (or contract-linked bundle) in an isolated worktree
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, EnterPlanMode, ExitPlanMode, EnterWorktree, ExitWorktree]
argument-hint: <spec-id>
---

## Pre-check

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/precheck.sh initialized`. Non-zero → STOP and print stderr verbatim.
2. Exactly one `<spec-id>` argument required. Missing / multiple → STOP: "Usage: `/specflow:implement <spec-id>`. Implement one spec at a time."
3. Load `specs/<spec-id>.md`. Missing file → STOP: "Spec `<spec-id>` not found in `specs/`."
4. Check the spec's `status`. Only `draft` or `amended` are valid entry points. Others → STOP with the current status and a suggestion (`active` → already implemented; `deprecated` → recreate via `/specflow:spec`).
5. **Bundle expansion**: grep every spec file under `specs/` for `[contract] absorbed into <spec-id>`. Matching specs form the bundle and must ship together atomically. All bundle members must be `draft` or `amended`; mixed statuses → STOP listing the offenders.

## Overlap precheck

For every file currently covered by the target spec (and any bundle members), run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh list-by-spec <spec-id>` to collect covered paths, then `list-by-path <path>` to find other specs covering each path. Read those other specs.

For each (other-spec, path) pair, classify whether implementing the current spec plausibly breaks the other spec's `## Behavioral Contract`. Any **contract-breaking** finding → STOP and print the contract-drift follow-up message (see `references/conventions.md`), routing the user to `/specflow:spec --amend <other-spec-id>`. Resume after amendment.

## Working tree check

1. Record the starting branch: `git rev-parse --abbrev-ref HEAD`.
2. Require `git status --porcelain` to be empty. Dirty tree → STOP: "Working tree has uncommitted changes. Commit or stash first so the implementation lands as a clean staged diff."

## Plan + implement in a worktree

### Enter the worktree

`EnterWorktree` from current HEAD. All coding happens here. The worktree's branch is throwaway.

### Plan mode

Immediately call `EnterPlanMode`. While in plan mode, read:

- The target spec body (and any bundle members).
- INDEX rows covering this spec: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh list-by-spec <spec-id>`.
- Related specs that share files (already identified during overlap precheck), read-only.
- Relevant source files.

Write the implementation plan into Claude Code's plan file. Transform each unchecked `## Acceptance Criteria` into a verifiable goal. Surface test coverage gaps.

Call `ExitPlanMode` to hand the plan to the user for approval.

### Code

Implement per the approved plan. Run available tests and builds inside the worktree after each significant change. Iterate until every acceptance criterion holds. Commit inside the worktree freely or not at all — the branch is throwaway.

### Exit the worktree

Once the user is satisfied, `ExitWorktree action: "keep"` to return to the starting branch.

## Merge back as staged diff

Specflow never commits on the starting branch. Bring the worktree's work back as a staged diff:

1. `git merge --squash <worktree-branch>`. Conflicts → STOP: print the conflict files, leave the worktree branch intact, instruct the user to `git merge --abort` (or resolve manually) and re-run `/specflow:implement <spec-id>`.

## Reconcile

Invoke the reconcile subroutine (`references/reconcile.md`) with:

- `<changeset>` = `git diff --name-status --cached`
- `<base>` = `<starting-branch>` (change-history wording only)
- `allow_skip = false`
- `may_rewrite_contract = false`
- `hash_source = worktree`

Contract-breaking findings → STOP and print the contract-drift follow-up message (see conventions), routing the user to `/specflow:spec --amend <other-spec-id>`. Recovery steps: `git reset --hard` to discard the squash, run `/specflow:spec --amend`, then re-run `/specflow:implement`. Leave the worktree intact so the user can re-enter if they need it.

## Update INDEX

From the staged diff (`git diff --name-status --cached`), for each path and every spec in the bundle:

- **A / M / T** (production) → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh upsert <path> <spec-id> $(git hash-object <path> | cut -c1-7)`
- **A** (test) → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh upsert <path> <spec-id> -`
- **D** → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh remove <path>` (or `remove <path> <spec-id>` if the path stays in other specs)
- **R** → remove old path, upsert new path.

Only touch this spec's (bundle's) rows unless reconcile's Step 3 flagged a cross-spec hash refresh as uniformly hash-only.

## Update spec bodies

For each spec in the bundle:

- Tick off completed `## Acceptance Criteria`.
- Append to `## Change History`: `- <YYYY-MM-DD>: <one-line summary of what shipped>`.
- Flip frontmatter `status` → `active`.

These edits are unstaged — the user stages them before committing.

## Cleanup

1. `git worktree remove <worktree-path>`
2. `git branch -D <worktree-branch>`

Safe because the squash-merge already absorbed the work.

## Report

- Spec IDs shipped (bundle members)
- Files touched (from the staged diff)
- Close with: **"Code is staged. Spec + INDEX edits are unstaged. Review `git status` and commit at your own pace — specflow never commits for you."**
