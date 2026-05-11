---
description: Detect code changes since free mode started and sync feature documentation
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
---

## Pre-check

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/precheck.sh free-active`. Non-zero exit → STOP and print the script's stderr verbatim.

## Steps

### Detect changes

Read `commitId` from `.docflow/state`. Run `git diff --name-status <commitId> HEAD` to build the changeset (`M` / `A` / `D` / `R` / `T`).

Empty changeset → tell the user "No committed changes detected since free mode started.", delete `.docflow/state`, STOP.

### Reconcile

Invoke the reconcile subroutine in `references/reconcile.md` with:

- `<changeset>` = the name-status list above
- `<base>` = `commitId` from state
- `allow_skip = false` — free-mode changes must be documented
- `may_rewrite_contract = true` — commit may update `## Behavioral Contract` after `AskUserQuestion` approval (see conventions' contract write-permission matrix)

Register any `new_features` in `docs/INDEX.md` with status `active` (commit only sees already-implemented code, so a new feature here is born `active` — `commit` never produces `amended`; see the transition table in conventions).

### Clean up

Delete `.docflow/state`.

Summarize what was updated, then remind the user to commit the doc changes: `git add docs/ && git commit -m "docs: sync feature documentation"`.

If the reconcile output contains any `contract_drift` entries, print the contract-drift follow-up message (see conventions) so the user can run `/docflow:plan --amend` for any files left as unclear contract impact.
