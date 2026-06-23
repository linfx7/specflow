---
description: Implement a single spec (or contract-linked bundle) on an isolated throwaway branch
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, EnterPlanMode, ExitPlanMode]
argument-hint: <spec-id>
---

## Pre-check

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/precheck.sh initialized`. Non-zero → STOP and print stderr verbatim.
2. Exactly one `<spec-id>` argument required. Missing / multiple → STOP: "Usage: `/specflow:implement <spec-id>`. Implement one spec at a time."
3. Load `specs/<spec-id>.md`. Missing file → STOP: "Spec `<spec-id>` not found in `specs/`."
4. Check the spec's `status`. Only `draft` or `amended` are valid entry points. Others → STOP with the current status and a suggestion (`active` → already implemented; `deprecated` → recreate via `/specflow:spec`).
5. **Bundle expansion**: run `grep -lF "[contract] absorbed into <spec-id>" specs/spec-*.md` (use `-F`: `[contract]` is a literal marker, not a regex character class — without it the brackets are read as a class and the match silently misbehaves). Matching specs form the bundle and must ship together atomically. All bundle members must be `draft` or `amended`; mixed statuses → STOP listing the offenders.

## Overlap precheck

For every file currently covered by the target spec (and any bundle members), run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh list-by-spec <spec-id>` to collect covered paths, then `list-by-path <path>` to find other specs covering each path. Read those other specs.

For each (other-spec, path) pair, classify whether implementing the current spec plausibly breaks the other spec's `## Behavioral Contract`. Any **contract-breaking** finding → STOP and print the contract-drift follow-up message (see `${CLAUDE_PLUGIN_ROOT}/references/conventions.md`), routing the user to `/specflow:spec --amend <other-spec-id>`. Resume after amendment.

## Working tree check

1. Record the starting ref: `START=$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)`. On a branch this is the branch name; on a detached HEAD it's the commit SHA. (Plain `git rev-parse --abbrev-ref HEAD` would wrongly return the literal string `HEAD` when detached, and the later `git checkout "$START"` would not return to the right commit.)
2. Require `git status --porcelain` to be empty. Dirty tree → STOP: "Working tree has uncommitted changes. Commit or stash first so the implementation lands as a clean staged diff."

## Plan + implement on a throwaway branch

The isolation is a throwaway branch, created and torn down with plain `git`. Coding happens **in place** on that branch (the working directory is its checkout), so normal relative paths edit the right files — no separate worktree directory, no CWD switching. Because the branch is named per spec (`specflow/<spec-id>`), several specs can be implemented in parallel from separate git worktrees without colliding.

### Create the throwaway branch

Do this **before** entering plan mode and before editing anything — otherwise the first edit could land on the starting branch, and the squash/checkout logic below would break.

1. Guard against a leftover from a prior aborted run: if `git rev-parse --verify --quiet "specflow/<spec-id>"` succeeds, STOP and tell the user to delete it (`git branch -D specflow/<spec-id>`) or rename it, then re-run. Never silently delete it — it may hold unrecovered work. (Across parallel worktrees this also stops two sessions grabbing the same spec.)
2. `git checkout -b "specflow/<spec-id>"` (branches from the current HEAD, i.e. `$START`). All coding happens here.

### Plan mode

Call `EnterPlanMode` (now on the throwaway branch). While in plan mode, read:

- The target spec body (and any bundle members).
- INDEX rows covering this spec: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh list-by-spec <spec-id>`.
- Related specs that share files (already identified during overlap precheck), read-only.
- Relevant source files.

Write the implementation plan into Claude Code's plan file. Transform each unchecked `## Acceptance Criteria` into a verifiable goal. Surface test coverage gaps.

Call `ExitPlanMode` to hand the plan to the user for approval. If the user rejects or aborts, undo the branch and STOP: `git checkout "$START"` then `git branch -D "specflow/<spec-id>"`.

### Code

Implement per the approved plan (only now, on the throwaway branch — no edits before the branch exists). Run available tests and builds after each significant change. Iterate until every acceptance criterion holds.

When the user is satisfied, commit everything to the throwaway branch so the switch back is clean:

```
git add -A && git -c user.name=specflow -c user.email=specflow@local commit -m "specflow: implement <spec-id>"
```

The `-c` flags let the commit succeed even when the repo has no configured git identity; the commit lives **only** on the throwaway branch (deleted at the end), so its author and existence never reach the starting branch. If there was nothing to implement and the commit would be empty, skip it.

## Merge back as staged diff

Specflow never commits on the starting branch. Bring the throwaway branch's work back as a staged diff:

1. `git checkout "$START"` — return to the starting ref (tree is clean because all work was committed on the throwaway branch).
2. `git merge --squash "specflow/<spec-id>"` — applies the cumulative diff and stages it **without committing**. Conflicts (only possible if the starting branch moved underneath you) → STOP: print the conflict files, run `git merge --abort`, leave branch `specflow/<spec-id>` intact, and instruct the user to resolve and re-run `/specflow:implement <spec-id>`.

`git diff --cached` now holds the implementation, staged on the starting branch with no commit made.

## Reconcile

Invoke the reconcile subroutine (read `${CLAUDE_PLUGIN_ROOT}/references/reconcile.md` via `cat`) with:

- `<changeset>` = `git diff --name-status --cached`
- `<base>` = `$START` (change-history wording only)
- `allow_skip = false`
- `may_rewrite_contract = false`
- `hash_source = working-tree`

Contract-breaking findings → STOP and print the contract-drift follow-up message (see conventions), routing the user to `/specflow:spec --amend <other-spec-id>`. Recovery steps: `git reset --hard` to discard the staged squash, run `/specflow:spec --amend`, then re-run `/specflow:implement`. Leave branch `specflow/<spec-id>` intact so its work isn't lost — the user can `git checkout` it if they need to.

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

`git branch -D "specflow/<spec-id>"` — safe because the squash-merge already absorbed the work into the staged diff on the starting branch.

## Report

- Spec IDs shipped (bundle members)
- Files touched (from the staged diff)
- Close with: **"Code is staged. Spec + INDEX edits are unstaged. Review `git status` and commit at your own pace — specflow never commits for you."**
