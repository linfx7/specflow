---
description: Check consistency between code and feature documentation
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
---

## Pre-check

Run `bash scripts/precheck.sh no-state`. Non-zero exit → STOP and print the script's stderr verbatim.

## Steps

### Scan for drift

Run `bash scripts/detect-drift.sh`. Exit codes:

- `0` — repo is in sync. Tell the user everything is consistent and STOP.
- `10` — drift records on stdout (see format below). Continue.
- `2` — fatal (missing INDEX, git failure). STOP and print stderr.

Each stdout line is TAB-separated: `kind\tfeature\tpath\textra1\textra2`. Kinds:

| Kind | Meaning |
|------|---------|
| `HASH_MISMATCH` | `feature` recorded `extra1`, disk has `extra2`. Needs contract classification. |
| `SHARED_DIVERGE` | `path` appears in multiple features with divergent hashes; disk hash in `extra1`; feature:hash pairs in `extra2`. |
| `MISSING_FILE` | `path` listed under `feature`'s `## Associated Files` but gone from disk. |
| `UNTRACKED_SRC` | `path` is a source file on disk, listed in no feature's `## Associated Files`. |
| `MISSING_TEST` | test `path` listed under `feature`'s `## Tests` but gone from disk. |
| `ORPHAN_TEST` | test `path` on disk not in any feature's `## Tests`. |
| `ORPHAN_DOC` | doc at `path` has no INDEX entry. |
| `MISSING_DOC` | INDEX lists `feature` but no doc file exists. |
| `DUP_ID` | `path` column holds a duplicated feature ID. |

### Classify and resolve

Read `references/conventions.md` and `references/reconcile.md` once. Then:

**Automatic (no prompt):**

- `HASH_MISMATCH` where the disk hash matches **another** feature's `SHARED_DIVERGE` truth-hash → refresh stale entries to the truth-hash.
- `SHARED_DIVERGE` with a disk-match hash (`extra1` not `-`) → auto-refresh all non-matching entries to `extra1`. No change-history entry (contract hasn't moved).

**Needs LLM judgment:**

- Remaining `HASH_MISMATCH` — for each, read the file and classify against the feature's `## Behavioral Contract`:
  - **Hash-only drift** → refresh hash silently.
  - **Likely contract drift** → do NOT refresh hash; add to contract-drift output.
  - Unsure → default to hash-only; note in summary.
- `MISSING_FILE` — check `UNTRACKED_SRC` for same-content-hash or similar-name match. Match → treat as rename; update path, refresh hash. No match → `AskUserQuestion`: (a) remove from associations (b) deprecate feature if all associated files are gone (c) skip.
- `UNTRACKED_SRC` that didn't rename-match → `AskUserQuestion`: (a) assign to existing feature (b) create new feature (template from `references/feature-template.md`) (c) ignore.
- `MISSING_TEST` → `AskUserQuestion`: (a) remove from `## Tests` (b) keep (c) skip.
- `ORPHAN_TEST` → `AskUserQuestion`: (a) add to existing feature's `## Tests` (b) create new feature (c) ignore.
- `ORPHAN_DOC` → `AskUserQuestion`: (a) add to INDEX.md (b) delete doc (c) skip.
- `MISSING_DOC` → `AskUserQuestion`: (a) create from template (b) remove INDEX entry (c) skip.
- `DUP_ID` → `AskUserQuestion`: (a) reassign one to a new ID (b) skip.

Sync **never** rewrites `## Behavioral Contract`. Contract-breaking findings route to `/docflow:plan --amend` via the contract-drift output (see `may_rewrite_contract = false` in `references/reconcile.md`).

### Feature-level checks (no script coverage)

These need INDEX + feature-doc reading, not just drift scanning:

1. **Status mismatch**: `active`/`amended` with empty `## Associated Files` → prompt to deprecate. `deprecated` with live code → prompt to reactivate. `amended` feature whose latest `[contract]` entry's implied `## Acceptance Criteria` are all ticked → prompt to flip to `active`.
2. **Stale planned**: `planned` feature with no associated files and no change-history updates in 30+ days → prompt: (a) keep (b) remove feature entirely (c) skip.

### Report

Print a summary of what changed. If any Likely contract drift findings exist, print the contract-drift follow-up message (see conventions) so the user can run `/docflow:plan --amend`.

List any features with status `planned` and suggest `/docflow:implement`.
