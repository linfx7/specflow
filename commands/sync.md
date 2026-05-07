---
description: Check consistency between code and feature documentation
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
---

## Pre-check

1. `docs/INDEX.md` missing → STOP: "docflow is not initialized. Run `/docflow:init` first."
2. `.docflow/state` exists → STOP: "A session is already active. Run `/docflow:plan` (flow) or `/docflow:commit` (free) to finish it, or delete `.docflow/state` to discard it."

## Steps

### Read current state

Read `references/conventions.md`, `docs/INDEX.md`, and all feature docs in parallel. Collect associated file paths + hashes (from `## Associated Files`) and test file paths (from `## Tests`).

Malformed `docs/INDEX.md` YAML frontmatter → STOP and show the parse error.

### Detect inconsistencies

Run all checks. Nothing found → tell the user everything is in sync and STOP.

**Production code checks (`## Associated Files`):**

1. **Hash mismatch**: compute current hash for each associated file. For each mismatch, collect its content in a single parallel batch, then apply contract classification (see conventions):
   - **Hash-only drift**: contract still holds
   - **Likely contract drift**: contract broken; capture a 1-2 sentence reason
2. **Shared-file hash divergence**: for files listed in more than one feature's `## Associated Files`, compare the recorded hashes across features. Differences (regardless of disk match) mean some feature missed a cross-feature refresh. Pick the hash that matches disk as the truth; if none matches, treat as regular hash mismatch and require user choice during resolve.
3. **Missing files**: associated files that no longer exist. Flag partial if only some files of a feature are deleted.
4. **Possible renames**: cross-reference missing files with untracked files — match by similar name or identical content hash. Flag as rename rather than delete + add.
5. **Untracked source files**: run `git ls-files --cached --others --exclude-standard`, then partition. Exclude non-source patterns (see conventions) and test file patterns (handled below). Source files not listed in any feature's `## Associated Files` are untracked.

**Test file checks (`## Tests`):**

6. **Missing tests**: test files listed in `## Tests` that no longer exist on disk.
7. **Orphan tests**: test files (see conventions) on disk not listed in any feature's `## Tests`. Reuse the `git ls-files` output from step 5.

**Feature-level checks:**

8. **Status mismatch**: `active` or `amended` features whose associated files are all deleted, or `deprecated` features with live code. Also, `amended` features whose latest `[contract]` change history entry has all its implied `## Acceptance Criteria` checked — code caught up, status should be `active`.
9. **Stale planned**: `planned` features with no associated files and no change history updates in 30+ days.

**Index integrity checks:**

10. **INDEX/doc mismatch**: docs in `docs/features/` without INDEX entry, or INDEX entries without a doc file.
11. **Duplicate IDs**: same ID used by multiple features in INDEX.md.

### Resolve

| Issue | Resolution |
|-------|------------|
| Hash-only drift | Auto-refresh hash (no prompt) |
| Likely contract drift | Do NOT refresh hash. Emit a contract-drift follow-up entry (see conventions). |
| Shared-file hash divergence (one hash matches disk) | Auto-refresh all stale entries to the matching hash (no prompt) |
| Shared-file hash divergence (none matches disk) | Handled as Hash mismatch above — one classification, then refresh all features together |
| Missing files | (a) Remove from associations (b) Deprecate feature (c) Skip |
| Possible rename | (a) Update path + refresh hash (b) Treat as delete + add (c) Skip |
| Untracked source file | (a) Associate with existing feature (b) Create new feature (template from `references/feature-template.md`) (c) Ignore |
| Missing tests | (a) Remove from `## Tests` (b) Keep (c) Skip |
| Orphan test | (a) Add to existing feature's `## Tests` (b) Create new feature (c) Ignore |
| Status mismatch | (a) Update status (b) Skip |
| Stale planned | (a) Keep (b) Remove feature entirely (c) Skip |
| Orphan doc | (a) Add to INDEX.md (b) Delete doc (c) Skip |
| Missing doc | (a) Create from template (b) Remove INDEX entry (c) Skip |
| Duplicate IDs | (a) Reassign one to new ID (b) Skip |

Apply resolutions. If any Likely contract drift findings exist, print the contract-drift follow-up message (see conventions) at the end.

List any features with status `planned` and suggest `/docflow:implement`.
