## Spec IDs

`spec-NNN-name` format. `NNN` is a zero-padded sequence number, allocated by `scripts/index.sh next-id` (which scans `specs/spec-*.md` filenames and the INDEX's spec-id set for `max(NNN) + 1`). Name is a slug: lowercase letters, digits, hyphens. Example: `spec-001-user-login`. Padding width grows naturally — once you hit `spec-100`, new IDs stay at 3 digits; once you hit `spec-1000`, they grow to 4.

## File hash

7-character short hash of the working-tree file: `git hash-object <path> | cut -c1-7`. All commands (`init`, `implement`, `sync`) read from the working tree so stored hashes reflect exactly what the user sees on disk.

Test files are not hashed — their INDEX row carries `-` in the hash column. Tests evolve alongside behavior, and tracking their hash produces constant false-positive drift.

Note: `git hash-object` hashes raw working-tree bytes without applying `.gitattributes` clean filters. Specflow is internally consistent (same method on both sides of every comparison), so this doesn't cause drift — just be aware that a row's hash may not match `git rev-parse HEAD:<path>`.

## INDEX schema

`specs/INDEX` is a TSV file (no extension) — machine-first, human-scannable.

```
# specflow index v1
# lang: en    baseline: a1b2c3d
src/auth/login.ts	spec-001-user-login	abc1234
src/auth/middleware.ts	spec-002-session,spec-004-rate-limit	7f3b1a0
tests/auth/login.test.ts	spec-001-user-login	-
```

- First two lines are comments (`^#`). All readers filter them out.
- Header comment line 2 carries two keys:
  - `lang: <code>` — `en` | `zh` | other — chosen at `init` time; `/specflow:spec` uses it to pick the output language.
  - `baseline: <commit>` — commit hash the last successful `sync` saw as clean; used by `sync` as the fast-diff anchor.
- Body rows: `<path>\t<spec-id-list>\t<hash>`, sorted alphabetically by path.
- **Column 2** is a comma-separated list of spec IDs that cover this path, kept alphabetically sorted for stable diffs. One row per path — never two rows for the same path.
- Hash is a property of the path, so every spec in the list shares it. This rules out "same path, different hashes across specs" drift by construction (no `SHARED_DIVERGE` kind needed).
- Canonical awk filter for body rows: `$1 !~ /^#/ && NF==3`.

Use `scripts/index.sh` for all reads and mutations. Hand-editing is supported but the script keeps rows sorted and spec-id lists normalized.

## Spec file shape

Spec files live at `specs/spec-NNN-name.md`. Frontmatter + three required sections:

- `## Behavioral Contract` — observable behaviors, one bullet per rule. No implementation detail.
- `## Acceptance Criteria` — testable checkboxes.
- `## Edge Cases` — optional; list only non-obvious behaviors.
- `## Change History` — append-only log.

Body rule: Behavioral Contract + Acceptance Criteria ≤ 40 lines combined. Long edge-case lists are fine; prose walls are not.

Specs do **not** list associated files or tests. That mapping lives in `specs/INDEX` (one path → many specs supported). Keeping it out of spec bodies keeps specs short and readable.

Frontmatter:

- `id`: spec ID (see "Spec IDs").
- `name`: short human-readable title.
- `status`: one of `draft`, `active`, `amended`, `deprecated`.
- `deps`: list of spec IDs this one depends on.

## Status lifecycle

- `draft` — spec exists, code doesn't yet (new work that hasn't been implemented).
- `active` — spec and code are in sync.
- `amended` — spec has moved ahead of code (contract was updated; implementation catching up).
- `deprecated` — spec retired; all covered files are gone.

Transitions owned by commands:

| Transition | Triggered by |
|------------|--------------|
| `→ active` at init | `init` creates specs for existing code |
| `→ draft` | `spec` creates a new spec for unbuilt behavior |
| `active → amended` | `spec --amend` (or `spec` absorbing a contract-breaking change on a shared file) |
| `draft` / `amended` → `active` | `implement` merges code back |
| `active` / `amended` → `deprecated` | `sync` when all covered files are gone |

## Test file patterns

Paths matching any of: `**/*.test.*`, `**/*_test.*`, `**/test_*.*`, `tests/**`, `__tests__/**`. INDEX rows for test files carry `-` in the hash column.

## Non-source files

Excluded when scanning for untracked source. Kept narrow — Dockerfile, Makefile, CI configs, package manifests, and YAML/TOML are code-like and deserve spec association.

Exclude only:

- Specflow's own artifacts: `specs/**`
- Git internals: `.git/**`
- Generated lockfiles: `*.lock`, `*-lock.json`, `go.sum`
- Boilerplate: `LICENSE*`, `CLAUDE.md`, root-level `README.md`

Everything else is eligible — let `sync` flag it and ask the user rather than pre-filtering.

## Change History entry format

One line per entry, appended chronologically:

```
- <YYYY-MM-DD>: <brief description>
```

- Date: always `YYYY-MM-DD`. Never `YYMMDD` or locale forms.
- Separator: `:` then a single space.
- Description: one line, imperative or past-tense. No status tag (status lives in frontmatter).
- Prefix with `[contract]` if the entry updates `## Behavioral Contract`. Example: `- 2026-05-07: [contract] rename token field to session_id`.
- Contract-linked bundle entries share a single line on each absorbed spec: `- 2026-05-07: [contract] absorbed into spec-001-user-login`.

## Contract classification

When a production file changes, classify the diff against every spec that covers it:

- **Hash-only (no contract change)**: internal refactor, renamed locals, extracted helper, logging, formatting. Every covering spec's `## Behavioral Contract` still holds.
- **Contract-breaking**: signature change, new observable behavior, removed capability, changed error surface, changed return type. One or more covering specs are affected.

Because one path maps to many specs via INDEX column 2, classification runs per-(path, spec) — a diff may be hash-only for spec A and contract-breaking for spec B. Hash refresh (single-row INDEX edit) happens only when **every** covering spec classifies the diff as hash-only.

## Contract write-permission matrix

| Command | May write `## Behavioral Contract`? |
|---------|-------------------------------------|
| `spec` (new / `--amend`) | yes, after grill-me decisions |
| `init` | yes, inferred from existing code |
| `implement` | no — STOP and route user to `/specflow:spec --amend` |
| `sync` | no — STOP and route user to `/specflow:spec --amend` |

Contracts are human-reviewed design. Commands that see code-level changes (`implement`, `sync`) never silently update a contract.

## Contract-drift follow-up message

When `implement` or `sync` detects contract-breaking impact on one or more specs, print:

```
Contract drift <detected|pending resolution>:

  - <spec-id>: <file-path> — <one-line reason>
    → run: /specflow:spec --amend <spec-id>

After running the amend command(s), re-run <this command>.
```

One line per affected spec. If multiple specs cover the same file and a subset is contract-breaking, emit one line per contract-breaking spec.

## Language rule

All prompts and generated spec bodies use the `lang` value from the INDEX header. Mirror the user if they switch language mid-conversation, but the persisted spec text stays in the configured language for consistency across specs.
