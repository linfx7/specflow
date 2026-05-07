---
description: Detect code changes since free mode started and sync feature documentation
disable-model-invocation: true
allowed-tools: [Read, Write, Bash, Glob, Grep, AskUserQuestion]
---

## Pre-check

1. `docs/INDEX.md` missing → STOP: "docflow is not initialized. Run `/docflow:init` first."
2. `.docflow/state` must exist with `mode=free`:
   - Missing → STOP: "No active free mode session. Run `/docflow:free` first."
   - Different mode → STOP: "Current session is `<mode>`, not free. Run `/docflow:plan` to finish it, or delete `.docflow/state` to discard it."
3. Run `git branch --show-current`. If it doesn't match `branch` in state → STOP: "You started free mode on branch `<state.branch>` but are now on `<current>`. Switch back or delete `.docflow/state` to discard the session."
4. Run `git status --porcelain`. If non-empty → STOP: "Commit your code first. Docflow documents committed history, not uncommitted state. After committing, re-run `/docflow:commit`."

## Steps

### Detect changes

Read `commitId` from `.docflow/state`. Run `git diff --name-status <commitId> HEAD` to enumerate changed files with codes (`M` / `A` / `D` / `R` / `T`).

No changes → tell the user "No committed changes detected since free mode started.", delete `.docflow/state`, STOP.

### Analyze and match

Read `references/conventions.md` and `docs/INDEX.md` in parallel. Filter out non-source patterns (see conventions). Partition the rest into production files (`## Associated Files`) and test files (`## Tests`) using test patterns from conventions.

`Grep` the remaining paths against `docs/features/*.md`; read only matched docs.

Group changes by feature:
- File already listed in one or more features → auto-assign to all; no user prompt.
- Genuinely new file → prompt with `AskUserQuestion`:
  - Assign to an existing feature
  - Create a new feature (template from `references/feature-template.md`)

  Skipping is not offered — if docflow classifies it as source, it must be documented.

### Update documentation

For each affected feature:

1. Reconcile `## Associated Files` / `## Tests` per the "Name-status reconciliation" rule in conventions.
2. **Contract classification** (see conventions) for each production file with `M` / `T` / `R`, compared against the feature's current `## Behavioral Contract`:
   - **Hash-only**: leave the contract section alone.
   - **Contract-breaking**: use `AskUserQuestion` to show the diff and proposed rewording. Only update `## Behavioral Contract` after user approves.
   - Unsure → default to hash-only and surface a note in the summary (user can run `/docflow:plan --amend` if needed).
3. Update `## Key Implementation Notes` silently if the implementation approach changed (it's not a contract).
4. Update `## Acceptance Criteria` — check off completed items. If contract classification produced updates, prompt before adding new criteria.
5. Add a `## Change History` entry (see conventions for format).

Update `docs/INDEX.md` only if feature statuses changed via user decision (commit doesn't auto-change status).

### Clean up

Delete `.docflow/state`.

Summarize what was updated, then remind the user to commit the doc changes: `git add docs/ && git commit -m "docs: sync feature documentation"`. List any files left as unclear contract impact so the user can decide about `/docflow:plan --amend`.
