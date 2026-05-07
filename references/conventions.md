## Feature IDs

`feat-YYMMDD-name` format. The `feat-` prefix marks the ID as a feature (self-documenting in grep, commit messages, and cross-project references). Date prefix is today's date (creation date). Name is a slug: lowercase letters, digits, hyphens only. Example: `feat-260430-user-login`.

## File hash

7-character short hash of the committed blob: `git rev-parse HEAD:<path>`, truncated to 7 chars. Always read from HEAD, never from the working tree — this stays correct even when precommit hooks rewrote the working copy, and avoids `.gitattributes` clean-filter discrepancies.

## Associated Files line format

One line per production file under `## Associated Files`:

```
- <file-path> | <git-short-hash>
```

- Separator between path and hash: a single space, then `|`, then a single space.
- Path is repo-relative (same form as `git ls-files` output). No leading `./`.
- Hash is the 7-char short-hash defined above.
- Test files go under `## Tests` instead, path only, no hash (`- <test-file-path>`).
- A `planned` feature that has no production files yet leaves `## Associated Files` empty (no placeholder lines). `implement` is responsible for populating it from the committed diff.

## Name-status reconciliation

Given `git diff --name-status <base> HEAD` codes, apply per changed file:

- **M / T** (modified / type change): refresh hash in place (production); no change (test).
- **A** (added): production → append `- <path> | <hash>`; test → append `- <path>`.
- **D** (deleted): remove the entry from whichever list it was in. If this empties `## Associated Files` for an `active`/`amended` feature, flag for `deprecated` candidacy.
- **R** (renamed): update the path in place; refresh hash if production.

Hashes read via `git rev-parse HEAD:<path>` per the File hash rule above.

## Test file patterns

Paths matching any of: `**/*.test.*`, `**/*_test.*`, `**/test_*.*`, `tests/**`, `__tests__/**`.

## Non-source files

Paths excluded when scanning for untracked source files. Kept deliberately narrow — Dockerfile, Makefile, CI configs, project configs (package.json, pyproject.toml, etc.), and YAML/TOML are all real code-like artifacts that deserve feature association.

Exclude only:

- docflow's own artifacts: `docs/**`, `.docflow/**`
- Git internals: `.git/**`
- Generated lockfiles: `*.lock`, `*-lock.json`, `go.sum`
- Boilerplate: `LICENSE*`, `CLAUDE.md`, root-level `README.md`

Everything else (Dockerfile, Makefile, `.github/**`, `*.config.*`, `*.json`, `*.yaml`, `*.yml`, `*.toml`, `.gitignore`, `.editorconfig`, etc.) should be eligible for feature association. Let sync flag it as untracked and ask the user — don't pre-filter.

## INDEX.md schema

`docs/INDEX.md` is a YAML-frontmatter file listing every feature. Canonical shape:

```markdown
---
features:
  - id: feat-260430-user-login
    name: User login
    status: active
    dependencies: []
  - id: feat-260501-session-store
    name: Session store
    status: planned
    dependencies: [feat-260430-user-login]
---
```

- `id`: feature ID (see "Feature IDs").
- `name`: short human-readable title; matches the feature doc's first heading if any.
- `status`: one of `planned`, `amended`, `active`, `deprecated`. No other values.
- `dependencies`: list of feature IDs this one depends on. Empty list if none.

Status semantics:

- `planned` — contract decided, no production code yet.
- `amended` — production code exists but `plan` updated the contract and implementation hasn't caught up. The feature's `## Change History` has a `[contract]` entry and `## Acceptance Criteria` has unchecked items reflecting the new contract.
- `active` — contract and code are in sync.
- `deprecated` — feature retired; associated files no longer exist.

Status transitions owned by commands:

| Transition | Triggered by |
|------------|--------------|
| `→ planned` | `plan` creates a new feature |
| `active → amended` | `plan` absorbs a contract-breaking change into an already-active feature (if the absorbed feature is still `planned`, it stays `planned`) |
| `planned → active` | `implement` completes a planned feature |
| `amended → active` | `implement` catches the code up to an amended contract |
| `active → deprecated` | `sync` resolves "status mismatch" when all associated files are deleted, with user confirmation |
| `amended → deprecated` | same as above, for an amended feature |

`commit` updates code and contract atomically (code already matches the new contract), so the feature stays `active` — it never produces `amended`.

## Change History entry format

One line per entry, appended chronologically:

```
- <YYYY-MM-DD>: <brief description>
```

- Date: always full `YYYY-MM-DD` (today's date). Do not use `YYMMDD`, locale forms, or alternate separators.
- Separator after date: `:` followed by a single space.
- Description: one line, imperative or past-tense. No status tag (`Planned`/`Implemented`) — status lives in `docs/INDEX.md`.
- Prefix with `[contract]` if the entry updates `## Behavioral Contract`. Example: `- 2026-05-07: [contract] rename export format to NDJSON`.
- Contract-linked bundle entries share a single line referencing the driving feature: `- 2026-05-07: [contract] absorbed into feat-260430-user-login`.

## Contract classification

When a production file changes, classify the diff:

- **Hash-only (no contract change)**: internal refactor, renamed locals, extracted helper, logging, formatting. Declared `## Behavioral Contract` still holds.
- **Contract-breaking**: signature change, new observable behavior, removed capability, changed error surface, changed return type. Declared contract is affected.

## Contract write-permission matrix

| Command | May write `## Behavioral Contract`? |
|---------|-------------------------------------|
| plan (flow / amend) | yes, after grill-me decisions |
| commit | yes, after `AskUserQuestion` confirmation |
| implement | no — STOP and route user to `/docflow:plan --amend` |
| sync | no — STOP and route user to `/docflow:plan --amend` |

`## Key Implementation Notes` may be written silently by plan, commit, and implement (it's not a contract).

## Contract-drift follow-up message

When implement or sync detects contract-breaking impact on other features, print:

```
Contract drift <detected|pending resolution>:

  - <feature-id>: <file-path> — <one-line reason>
    → run: /docflow:plan --amend <feature-id>

After running the amend command(s), re-run <this command>.
```
