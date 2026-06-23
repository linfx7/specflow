---
description: Fast, INDEX-driven drift check between specs and code
disable-model-invocation: true
allowed-tools: [Read, Edit, Bash, Glob, Grep, AskUserQuestion]
---

## Pre-check

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/precheck.sh initialized`. Non-zero → STOP and print stderr verbatim.

## Steps

### Scan

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-drift.sh`. Exit codes:

- `0` — repo is in sync. Print a clean message. Optionally refresh the baseline (see Update baseline below) and STOP.
- `10` — drift records on stdout (TSV). Continue.
- `2` — fatal. Print stderr and STOP.

Record kinds (TAB-separated; field 2 is the spec-id list, field 3 is the path):

| Kind | Meaning |
|------|---------|
| `HASH_MISMATCH` | `path` recorded `extra1`, disk hash is `extra2`; covered by every spec in field 2. |
| `MISSING_FILE` | `path` in INDEX but gone from disk; covered by every spec in field 2. |
| `UNTRACKED_SRC` | source-like file on disk, in no INDEX row. |
| `MISSING_SPEC` | INDEX references `spec-id` (field 2) with no `specs/<id>.md`. |
| `ORPHAN_SPEC` | non-draft spec file at `path` has no INDEX rows. |
| `DUP_ID` | frontmatter `id` (field 3) duplicated across spec files. |

Test rows (hash `-`) participate only in `MISSING_FILE` (test vanished) and `UNTRACKED_SRC` (test appeared). Same resolver, shorter prompts.

### Resolve

Read `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` and `${CLAUDE_PLUGIN_ROOT}/references/reconcile.md` once (via `cat`). Sync uses reconcile.md as a **rules reference** — the hash-only-vs-contract-breaking classification (Step 2.2) and the deprecate-when-coverage-empties rule (Step 2.1) — and applies them to the drift *records* below. It does not execute reconcile's changeset-code (M/A/D/R) procedure; that path is for `implement`. The INDEX-integrity kinds (`MISSING_SPEC`, `ORPHAN_SPEC`, `DUP_ID`) are sync-only and not covered by reconcile. Classify each record.

**Automatic — no prompt:**

- `HASH_MISMATCH` where the diff classifies as **hash-only** (per conventions "Contract classification") against **every** spec in field 2 → refresh the INDEX row with the disk hash via `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh upsert <path> <any-spec-in-list> <disk-hash>` (upsert preserves the full list).
- If classification is unsure and lean toward hash-only → refresh but surface a note in the summary.

**Escalate (contract drift):**

- `HASH_MISMATCH` classified as **contract-breaking** for one or more specs in field 2 → **do NOT refresh the hash**. Emit one contract-drift entry per affected spec. Route to `/specflow:spec --amend <spec-id>` (see conventions → "Contract-drift follow-up message"). Sync must never rewrite `## Behavioral Contract`.

**LLM judgment — prompt:**

- `MISSING_FILE` → look for a rename match in the current `UNTRACKED_SRC` set by comparing `git hash-object`. Match found → auto-update the INDEX row's path (`index.sh remove <old>` + `index.sh upsert <new> <spec-id> <hash>`; do this for every spec in field 2). No match → `AskUserQuestion`: (a) drop the row entirely (`index.sh remove <path>`), (b) deprecate any spec whose remaining coverage is now empty (frontmatter `status: deprecated`, Change History entry), (c) skip.
- `UNTRACKED_SRC` (after rename matching) → `AskUserQuestion`: (a) assign to an existing spec (append via `index.sh upsert <path> <spec-id> <hash>`), (b) ignore, (c) suggest `/specflow:spec` to cover it later.
- `MISSING_SPEC` → `AskUserQuestion`: (a) recreate from `${CLAUDE_PLUGIN_ROOT}/references/spec-template.md` (then /specflow:spec --amend it to flesh out), (b) remove the id from INDEX (`index.sh remove <path> <spec-id>` for every path listing that id), (c) skip.
- `ORPHAN_SPEC` → `AskUserQuestion`: (a) add to INDEX by assigning paths to the spec via `/specflow:spec --amend <spec-id>`, (b) delete the spec file, (c) skip.
- `DUP_ID` → `AskUserQuestion`: (a) rename one spec file + update its frontmatter id to a fresh `next-id`, (b) skip.

### Update baseline

After the resolution pass, if the working tree is clean (`git status --porcelain` empty) and `detect-drift.sh` now returns `0`, update the baseline to HEAD: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh set-baseline $(git rev-parse --short=7 HEAD)`. Next sync uses this as the fast-diff anchor.

Do not update the baseline if drift remains unresolved or the working tree is dirty — otherwise the fast-path would skip legitimately-changed files.

### Report

Print a summary of what changed:

- Rows auto-refreshed (hash-only).
- Rows skipped pending contract amendment.
- Prompts the user answered.
- Baseline status (updated / unchanged).

If any contract-drift entries exist, print the contract-drift follow-up message (see conventions). List each affected spec and the `/specflow:spec --amend <spec-id>` command the user should run. Then `/specflow:implement <spec-id>` to catch the code up.
