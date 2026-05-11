# Reconcile subroutine

Shared procedure for applying a changeset to feature documentation. Called by `commit`, `implement`, and `sync`. Keeps per-file classification, per-feature updates, and cross-feature hash handling in one place so callers don't drift.

Callers operate on **committed state** only (`HEAD`). Ensure `git status --porcelain` is empty before invoking.

## Inputs

- `<changeset>`: list of `(path, code)` pairs where `code ∈ {M, A, D, R, T}`. Typically from `git diff --name-status <base> HEAD`; `sync` synthesizes it from whole-repo checks.
- `<base>`: commit or branch used as the diff base (for change-history wording only).
- `allow_skip` (bool): whether the user may ignore a new source file during matching.
  - `commit`, `implement`: `false` — if docflow classifies a file as source, it must be documented.
  - `sync`: `true` — sync scans the whole repo and may legitimately see files the user wants to leave out.
- `may_rewrite_contract` (bool): whether this call may update `## Behavioral Contract` in place. See the contract write-permission matrix in `conventions.md`.
  - `commit`: `true` (after `AskUserQuestion` approval).
  - `implement`, `sync`: `false` — emit contract-drift follow-up and route to `/docflow:plan --amend`.

## Step 1 — Analyze and match

Read `references/conventions.md` and `docs/INDEX.md` in parallel. Filter the changeset using the non-source patterns in conventions; partition the rest into production files and test files using the test patterns.

`Grep` the remaining paths against `docs/features/*.md`; read only matched docs.

Group the changeset by feature:

- **Known file** (already under some feature's `## Associated Files` or `## Tests`): auto-assign to every listing feature. No prompt.
- **Unknown file**: prompt with `AskUserQuestion`:
  - Assign to an existing feature
  - Create a new feature (template from `references/feature-template.md`, ID per conventions)
  - Ignore — offered only if `allow_skip == true`

## Step 2 — Per-feature updates

For each affected feature:

1. **Name-status reconciliation** of `## Associated Files` and `## Tests` per conventions.

2. **Contract classification** for every production file with code `M` / `T` / `R`, compared against the feature's `## Behavioral Contract`:
   - **Hash-only drift**: leave the contract section alone (the hash is already refreshed by step 1).
   - **Contract-breaking**:
     - `may_rewrite_contract == true` → `AskUserQuestion` with the diff and proposed rewording; only update `## Behavioral Contract` after approval, then update `## Acceptance Criteria` to match.
     - `may_rewrite_contract == false` → **do NOT refresh hash** for that file. Add the finding to the contract-drift output list; the caller decides whether to STOP or continue.
   - Unsure → default to hash-only and surface a note in the caller's summary.

3. **Key Implementation Notes**: update silently if the approach changed (not a contract).

4. **Acceptance Criteria**: tick off completed items. New criteria are added only as part of a contract rewrite.

5. **Change History**: append an entry per conventions. Contract rewrites use the `[contract]` prefix.

## Step 3 — Cross-feature hash refresh

For each production file in the changeset also listed in *another* feature's `## Associated Files`, classify the diff against that feature's contract:

- **Hash-only for the other feature** → refresh only its hash. No description, no change-history entry (contract hasn't moved for that feature).
- **Contract-breaking for the other feature** → same branching as Step 2: prompt if `may_rewrite_contract`, otherwise add to contract-drift output and skip the hash refresh for that feature.

## Step 4 — Shared-file hash divergence check

For every production file listed under more than one feature's `## Associated Files`, compare the recorded hashes across all listing features. If they differ:

- **One recorded hash matches disk** (`git rev-parse HEAD:<path>` truncated to 7): auto-refresh the other stale entries to that hash. No prompt, no change-history entry.
- **None matches disk**: reclassify per Step 2 against the shared contract(s); refresh all features together after resolution.

This check runs after Steps 1-3 so earlier refreshes are reflected. `scripts/detect-drift.sh` already emits `SHARED_DIVERGE` records covering the whole repo — sync consumes them directly; commit and implement can scope the check to the files they just changed by filtering the scanner's output or re-running it with their changeset in mind.

## Outputs

- **modified_features**: list of `{feature-id, reason}` for features whose docs changed.
- **new_features**: features created via Step 1's "create new" branch. Callers register these in `docs/INDEX.md`.
- **contract_drift**: `{feature-id, path, reason}` entries from contract-breaking findings with `may_rewrite_contract == false`. Callers print the contract-drift follow-up message (see conventions) when non-empty.

Reconcile does not touch `docs/INDEX.md` status (transitions are caller-owned — see the transition table in conventions) and does not commit.
