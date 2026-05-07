---
description: Initialize docflow in the current project
disable-model-invocation: true
allowed-tools: [Read, Write, Glob, Grep, Bash, AskUserQuestion]
---

## Pre-check

1. Run `git rev-parse --git-dir`. If it fails → STOP: "Not a git repository. Please run `git init` first."
2. Check initialization state:
   - `docs/INDEX.md` exists with valid YAML frontmatter → STOP: "docflow is already initialized. Use `/docflow:sync` to check documentation consistency."
   - `docs/` exists but `docs/INDEX.md` is missing or malformed → inspect `docs/` contents, then use `AskUserQuestion`:
     - Non-docflow content present: "(a) Add docflow files alongside existing content in `docs/`, (b) Use a different directory for docflow (specify name), (c) Abort"
     - Only docflow artifacts (empty or only `features/`): "(a) Continue initialization (reuse existing `docs/features/` if present), (b) Clean up docflow files and start fresh (removes only `docs/features/`, `docs/INDEX.md`, and `.docflow/`)"

## Writes

Non-obvious side effects:
- `.gitignore` — append `.docflow/` if not already present
- `CLAUDE.md` — create or append docflow snippet

## Steps

### Create directories

Create `docs/`, `docs/features/`, `.docflow/`. Add `.docflow/` to `.gitignore` (create `.gitignore` if missing).

### Analyze codebase

Run `git ls-files` (respects `.gitignore`). Filter out non-source files (see conventions).

- **Fresh project** (no source beyond config/boilerplate): write `docs/INDEX.md` with `features: []`, skip to **Update CLAUDE.md**.
- **Existing codebase**: proceed to **Generate docs**.

### Generate docs

Read `references/conventions.md`.

1. Scan the project and identify distinct functional modules that qualify as features (a feature is self-contained — readable without other features).
2. Show identified features as a table (ID, name, brief description). Use `AskUserQuestion` to adjust (add/remove/rename/merge).
3. For each feature, separate production files and test files (test patterns: see conventions).
4. After confirmation, batch-generate:
   - One feature doc per feature in `docs/features/<feat-YYMMDD-name>.md` from `references/feature-template.md`
   - `docs/INDEX.md` listing all features (status `active`)
   - Hashes for production files in `## Associated Files`; test files listed in `## Tests` (no hash)

### Update CLAUDE.md

Read `CLAUDE.md` and apply the docflow snippet:

- Doesn't exist → create it with the snippet.
- Contains a `<!-- docflow:start -->` block → diff against the snippet. Different → show the diff and use `AskUserQuestion` to confirm replacement. Identical → skip.
- Otherwise → append the snippet.

```markdown
<!-- docflow:start -->
## Docflow

Feature docs in `docs/features/` (indexed by `docs/INDEX.md`) are the source of truth for behavioral contracts.

- Exploring existing behavior: read feature docs first; fall back to source code when docs don't answer.
- **Free mode caveat**: with `.docflow/state` `mode=free`, docs may lag code — cross-check recently-changed areas. Reconciliation happens at `/docflow:commit`; `/docflow:sync` shows drift anytime.

## Coding Guidelines

- **Think before coding**: state assumptions explicitly. If uncertain, ask. If multiple interpretations exist, present them. Push back when a simpler approach exists.
- **Simplicity first**: minimum code that solves the problem. No speculative features, no abstractions for single-use code, no error handling for impossible scenarios.
- **Surgical changes**: touch only what you must. Don't improve adjacent code or formatting. Match existing style. Every changed line should trace directly to the request.
- **Goal-driven execution**: transform tasks into verifiable goals with success criteria. For multi-step tasks, state a brief plan with verification checks at each step.
<!-- docflow:end -->
```

Suggest `/docflow:brainstorm` to explore a feature, or `/docflow:free` to start coding and document later.
