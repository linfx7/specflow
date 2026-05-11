---
description: Implement planned features in isolated worktrees
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, Agent, EnterWorktree, ExitWorktree]
---

## Pre-check

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/precheck.sh no-state`. Non-zero exit → STOP and print the script's stderr verbatim.

## Steps

### Select features

Read `docs/INDEX.md`. List all features with status `planned` or `amended` as a table (ID, Name, Status, Dependencies). None → STOP: "No planned or amended features found. Run `/docflow:brainstorm` and `/docflow:plan` first."

**Detect contract-linked bundles** before building the selection UI: scan each `amended` / `planned` feature doc's `## Change History` for the most recent `[contract] absorbed into <feat-id>` marker (see conventions for format). Features sharing the same driving ID form one bundle; present the bundle as a single atomic option in `AskUserQuestion` — users cannot partially select it. Bundle members ship together or not at all.

Use `AskUserQuestion` to select one or more features / bundles.

### Dependency analysis

Read `references/conventions.md` and all feature docs in parallel (selected features AND their potential impact scope — grep other docs' `## Associated Files` for paths appearing in the selected features first, then read only matched docs).

Analyze:
1. **Dependency ordering**: if A depends on B and both are selected, B implements first. Flag circular deps.
2. **File overlap within selection**: warn about potential merge conflicts.
3. **Shared patterns**: identify common infrastructure needs.

### Contract-drift precheck

For each other feature reading the same files as a selected feature, apply contract classification (see conventions) against the planned changes. Any finding that's **contract-breaking** → STOP and emit the contract-drift follow-up message (see conventions). Plan should have caught these; halt rather than silently drift.

### Implement

Before entering any worktree, remember the **starting branch** (via `git rev-parse --abbrev-ref HEAD`). Worktrees merge back into this branch. Docflow does not manage the user's branch strategy — it only disposes of temporary worktree branches it created.

#### Single feature

`EnterWorktree` to create an isolated worktree. Implement the feature using the already-loaded feature doc:

- Transform each acceptance criterion into a verifiable goal
- Run tests/builds after each significant change

Once the user's code changes are committed inside the worktree, update documentation from the **committed** state by invoking the reconcile subroutine in `references/reconcile.md` with:

- `<changeset>` = `git diff --name-status <base-branch> HEAD`
- `<base>` = `<base-branch>`
- `allow_skip = false` — implement must document everything the user changed
- `may_rewrite_contract = false` — contract-breaking findings for the current feature OR any other feature mean the precheck missed drift; STOP and tell the user to run `/docflow:plan --amend <feature-id>` first. Leave the worktree and its branch intact; after the amend the user can merge the worktree manually or discard it and re-run `/docflow:implement`.

Then:

1. Check off completed `## Acceptance Criteria` on the current feature's doc. Reconcile's change-history entry covers the doc update; add feature-specific wording if the auto entry is too generic.
2. Commit the feature-doc updates inside the worktree (a distinct commit is fine). Do NOT touch `docs/INDEX.md` in the worktree — INDEX status writes only happen on the starting branch to avoid parallel-merge conflicts. `ExitWorktree` with `action: "keep"`.

Reconcile's Step 3 handles cross-feature hash refresh and its "Orphan test capture" — any test files added with code `A` not listed elsewhere get appended to the current feature's `## Tests` via the Step 1 "create new / assign to existing" prompt; surface the additions in the completion summary for user review.

**Merge and clean up** (on the starting branch):

1. `git merge --no-ff <worktree-branch>`. Conflicts → STOP: print the conflict files, leave the worktree branch intact, instruct the user to resolve manually — do not attempt automated resolution. After resolving, the user commits the merge and runs `/docflow:sync` to reconcile INDEX status and hashes.
2. Update `docs/INDEX.md`: status → `active` for every feature in this single/bundle unit. Commit as a follow-up on the starting branch.
3. Run the shared-file hash divergence check (reconcile Step 4 in `references/reconcile.md`). Any divergence must be auto-refreshed to the disk-matching hash before reporting done; commit the refresh as a follow-up on the starting branch if needed.
4. `git worktree remove <worktree-path>` and `git branch -d <worktree-branch>`.
5. Report: feature ID(s), merge commit SHA, files touched.

#### Multiple features

- **Independent** (no file overlap, no dependency): launch each as a parallel `Agent` with `isolation: "worktree"`. Each agent runs the full single-feature implementation block including its own feature-doc commit in-worktree (INDEX stays untouched), but agents do NOT merge — they only return their worktree branch name. Once all agents return, merge them serially into the starting branch in arbitrary order. Any merge conflict → STOP and surface to the user (remaining unmerged branches stay intact). After all successful merges, update INDEX statuses, run the shared-file hash divergence check once, then clean up all worktrees/branches.
- **Dependent**: implement sequentially in dependency order. Each follows the single-feature flow (merge + clean up) before the next starts, so later features see earlier features' code on the starting branch.
- **Contract-linked bundle** (selected atomically in "Select features"): implement together in a single worktree as one atomic unit — ship together or not at all. Single merge, single cleanup, all bundle members flipped to `active` together in the post-merge INDEX update.
