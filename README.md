# Specflow

Short, contract-focused specs that stay in sync with code. For committed code, **spec ≡ code** — read the spec first, source is the fallback.

## Why

Feature docs drift. Long docs get ignored. Specflow keeps a small, machine-indexed spec per behavior: contract + acceptance criteria, under ~40 lines, tied to the files that implement it. Code changes either preserve the contract (hash refresh, no spec edit) or break it (amend the spec first). No middle ground, no silent drift.

## Install

```
/plugin marketplace add linfx7/specflow
/plugin install specflow
```

## Commands

| Command | Description |
|---------|-------------|
| `/specflow:init` | Scan the project, propose specs for existing modules, create `specs/INDEX` with a language preference and a sync baseline. |
| `/specflow:spec [topic]` | Grill the user on a new behavior, then write the spec(s). `--amend <spec-id> [spec-id ...]` updates one or more existing specs in place. |
| `/specflow:implement <spec-id>` | Implement one spec (or a contract-linked bundle) on a throwaway branch, using plan mode. Squashes back as a staged diff; never commits. |
| `/specflow:sync` | Fast INDEX-driven drift scan. Refreshes hashes for hash-only changes; routes contract-breaking changes to `/specflow:spec --amend`. |

All commands are user-invoked (`disable-model-invocation: true`). Specflow never runs `git commit`.

## Data Model

```
specs/
  INDEX               # TSV. Header + one row per source/test path.
  spec-NNN-name.md    # One self-contained spec per file.
```

No `.specflow/` directory. No state files. No `.gitignore` edits.

### `specs/INDEX`

```
# specflow index v1
# lang: en    baseline: a1b2c3d
src/auth/login.ts	spec-001-user-login	abc1234
src/auth/middleware.ts	spec-002-session,spec-004-rate-limit	7f3b1a0
tests/auth/login.test.ts	spec-001-user-login	-
```

- Body rows: `<path>\t<spec-id-list>\t<hash>`, sorted by path.
- Column 2 is a comma-separated, alphabetically-sorted list of spec IDs that cover the path. One row per path.
- `hash` is the 7-char `git hash-object` of the working-tree file; `-` for tests (they evolve with behavior).
- Header carries `lang` (output language for spec bodies) and `baseline` (commit anchor for fast sync).

### Spec file

```markdown
---
id: spec-001-user-login
name: User login
status: active
deps: []
---

## Behavioral Contract
- POST /login with valid credentials returns a session token.
- Invalid credentials return 401 with `{"error":"invalid_credentials"}`.

## Acceptance Criteria
- [ ] Valid creds → 200 + JSON `{token: string}`
- [ ] Wrong password → 401 + error body

## Edge Cases
- Rate limit: >5 attempts/min per IP → 429.

## Change History
- 2026-05-13: Initial spec.
```

- **Behavioral Contract + Acceptance Criteria ≤ 40 lines.** Long prose walls are the smell specflow exists to prevent.
- Bodies do **not** list files or tests — INDEX is the authority.
- Status: `draft` → `active` → (`amended` → `active`) → `deprecated`. Transitions are command-owned.

## Contract Ownership

`## Behavioral Contract` is design. Only `spec` (new / `--amend`) and `init` write it; `implement` and `sync` STOP and route the user to `/specflow:spec --amend` instead. Full matrix in [`references/conventions.md`](references/conventions.md#contract-write-permission-matrix).

When code changes break a committed spec's contract, that's a signal — don't silently update the contract. Amend the spec or narrow the change.

## Typical Flow

**New behavior:**
1. `/specflow:spec add password reset` — grill, propose split, write spec file(s) with `status: draft`.
2. `/specflow:implement spec-005-password-reset` — throwaway branch + plan-mode + code + squash-merge. Spec flips to `active`; INDEX picks up the new rows.
3. User reviews `git status`, commits.

**Catching up to reality:**
1. `/specflow:sync` — if everything's a refactor, INDEX hashes refresh and the baseline advances.
2. If `sync` reports contract drift, run `/specflow:spec --amend <spec-id>` to nail down the new contract, then `/specflow:implement <spec-id>` to catch the code up.

## Plugin Structure

```
specflow/
  .claude-plugin/
    plugin.json
    marketplace.json
  commands/
    init.md, spec.md, implement.md, sync.md
  references/
    spec-template.md       # skeleton for new spec files
    conventions.md         # IDs, INDEX format, contract rules, lang rule
    reconcile.md           # shared changeset reconciliation
  scripts/
    precheck.sh            # init / initialized
    index.sh               # awk helpers over INDEX (list-by-path, upsert, next-id, …)
    detect-drift.sh        # TSV drift records; uses baseline for fast scan
```

## Design Principles

- Specs stay independent — new work shouldn't silently edit old specs.
- INDEX is machine-first. Mutations go through `scripts/index.sh` so rows stay sorted and spec-id lists stay deduped.
- `sync` uses a commit baseline to narrow scans to changed files only.
- All commands emit staged or unstaged changes; the user commits.

## Acknowledgements

- Grill-me interview style adopted from [grill-me](https://github.com/mattpocock/skills) by Matt Pocock.
- Coding guidelines in the CLAUDE.md snippet adapted from [andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) by Jiayuan Zhang.
