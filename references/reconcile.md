# Reconcile subroutine

Shared procedure for applying a changeset to specs + INDEX. Called by `implement` and `sync`. Keeps per-file classification, per-spec updates, and cross-spec hash handling in one place.

> Path convention: every `index.sh ...` below means `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh ...`, and every `references/...` is a plugin file read via `cat ${CLAUDE_PLUGIN_ROOT}/references/...`. Bare paths here would resolve against the user's project, not the plugin.

Both callers always pass `may_rewrite_contract = false`. Contract rewrites happen only inside `/specflow:spec` (default flow or `--amend`). So there is no "rewrite the contract in place" branch — contract-breaking findings always route the user to `/specflow:spec --amend`.

All hashes read via `git hash-object <path> | cut -c1-7` per conventions.md's File hash rule. The working tree is the single source of truth.

## Inputs

- `<changeset>`: list of `(path, code)` pairs where `code ∈ {M, A, D, R, T}`.
  - `implement`: `git diff --name-status --cached` inside the starting branch (the squash-merged diff).
  - `sync`: synthesized from the drift scan records (`HASH_MISMATCH`, `MISSING_FILE`, `UNTRACKED_SRC`, renames detected via same-hash match).
- `<base>`: commit or branch used for change-history wording only.
- `allow_skip` (bool): whether the user may ignore a new source file during matching.
  - `implement`: `false` — everything in the staged diff must land under some spec.
  - `sync`: `true` — sync scans the whole repo and may legitimately see files the user wants to leave out.
- `may_rewrite_contract`: always `false` for both callers.
- `hash_source`: `working-tree` (always, since we read via `git hash-object`).

## Step 1 — Analyze and match

Read `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` (via `cat`) and `specs/INDEX` in parallel. Filter the changeset using the non-source patterns in conventions; partition the rest into production files and test files using the test patterns.

Resolve each path's spec coverage via `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh list-by-path <path>`:

- **Known path** (already in INDEX): auto-assign to every spec in its list. No prompt.
- **Unknown path**: prompt with `AskUserQuestion`:
  - Assign to an existing spec (append to that path's spec-id list in INDEX)
  - Create a new spec later via `/specflow:spec` — record the path as pending and surface in the caller's summary
  - Ignore — offered only if `allow_skip == true`

In `implement` the target spec is already known, so unknown paths default to "assign to the target spec" unless they look like infrastructure shared with another spec — in which case prompt.

## Step 2 — Per-spec updates

For each affected spec + file:

1. **Name-status reconciliation** of INDEX rows per conventions:
   - **M / T**: refresh hash in place via `index.sh upsert <path> <spec-id> <new-hash>` (production); leave alone (test, hash stays `-`).
   - **A**: insert or merge via `index.sh upsert <path> <spec-id> <hash>` (production) or `<spec-id> -` (test).
   - **D**: drop via `index.sh remove <path> [<spec-id>]`. If this empties INDEX coverage for an `active`/`amended` spec (no paths remain under `list-by-spec <spec-id>`), flag the spec for `deprecated` candidacy in the caller's summary.
   - **R**: `index.sh remove <old-path>` then `index.sh upsert <new-path> …`.

2. **Contract classification** for every production file with code `M` / `T` / `R`, compared against the spec's `## Behavioral Contract`:
   - **Hash-only**: refresh hash (Step 2.1 already did this).
   - **Contract-breaking**: **do NOT refresh hash for that (path, spec) pair.** Add a `contract_drift` entry `{spec-id, path, reason}`. The caller decides whether to STOP or continue.
   - Unsure → default to hash-only and surface a note in the caller's summary.

   If a path maps to multiple specs and classification differs across them, **only refresh the hash when every covering spec classifies the diff as hash-only**. As soon as one spec calls it contract-breaking, the hash stays pinned (so the next `sync` will still flag the mismatch) and that spec gets a `contract_drift` entry.

3. **Acceptance Criteria**: tick off completed items where the change obviously satisfies them. Adding new criteria is not permitted here — that's a contract rewrite and happens in `/specflow:spec`.

4. **Change History**: append an entry per conventions. No `[contract]` prefix (contract rewrites don't happen in reconcile).

## Step 3 — Cross-spec hash consistency

Because INDEX is one-row-per-path with a shared hash column, there is no "same path, different hashes across specs" failure mode to reconcile. Step 3 simplifies to a single action:

For each path in the changeset whose row covers multiple specs, ensure the hash refresh in Step 2.1 was blocked by **no** spec's contract classification. If any covering spec was contract-breaking, the row's hash remains at its pre-change value and every covering spec gets a `contract_drift` entry (including the hash-only ones — they're fine, but the row is locked until the contract-breaking spec is amended).

## Outputs

- **modified_specs**: list of `{spec-id, reason}` for specs whose bodies changed (acceptance ticks, change history).
- **new_paths**: paths assigned to specs that didn't previously cover them (callers record these in INDEX via `upsert`).
- **contract_drift**: `{spec-id, path, reason}` entries. Callers print the contract-drift follow-up message (see conventions) when non-empty and route the user to `/specflow:spec --amend`.
- **deprecation_candidates**: spec IDs whose coverage emptied.

Reconcile does not touch spec `status` (caller-owned per the status lifecycle in conventions) and never runs `git commit`.
