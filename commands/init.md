---
description: Initialize specflow in the current project
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion]
---

## Pre-check

1. Run `git rev-parse --git-dir`. If it fails → STOP: "Not a git repository. Please run `git init` first."
2. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/precheck.sh init`. Non-zero → STOP and print stderr verbatim.
3. If `specs/` exists already, inspect its contents. If non-specflow content is present → `AskUserQuestion`: (a) add specflow files alongside existing content, (b) pick a different directory (abort — specflow isn't configurable here), (c) abort.

## Writes

- `specs/` — directory containing `INDEX` + one spec per module.
- `CLAUDE.md` — created or appended with the specflow snippet.

No `.specflow/` directory. No `.gitignore` edits. Specflow leaves no runtime artifacts.

## Steps

### Choose language

Inspect the surrounding conversation. If every user message so far is clearly English, default `lang=en` and skip the prompt. Otherwise ask with `AskUserQuestion`: "Which language should spec bodies and prompts use?" — options `en`, `zh`, `other` (free-text ISO code). The chosen value persists as `lang: <code>` in the INDEX header.

### Analyze codebase

Run `git ls-files` (respects `.gitignore`). Filter out non-source files per `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` → "Non-source files".

- **Fresh project** (no source beyond config/boilerplate): create `specs/`, write `specs/INDEX` with header-only content (no body rows), skip to **Update CLAUDE.md**.
- **Existing codebase**: proceed to **Generate specs**.

### Generate specs

Read `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` and `${CLAUDE_PLUGIN_ROOT}/references/spec-template.md` (via `cat`, so the variable expands — the Read tool does not expand it, and a bare `references/...` path would resolve against the user's project, not the plugin).

1. Scan the project and identify distinct functional modules that qualify as specs (one self-contained behavioral contract — readable without other specs).
2. Present the proposed split as a table: proposed ID (`spec-NNN-name` allocated sequentially from 001), name, brief description, covered files (production + tests). Use `AskUserQuestion` to let the user adjust — add / remove / rename / merge / split.
3. After confirmation, batch-generate:
   - One spec file per module at `specs/spec-NNN-name.md` from `${CLAUDE_PLUGIN_ROOT}/references/spec-template.md`, with `status: active`. Infer `## Behavioral Contract` from the code — describe intent, not implementation. Write in the configured language. Behavioral Contract + Acceptance Criteria ≤ 40 lines.
   - `specs/INDEX` with:
     - Line 1: `# specflow index v1`
     - Line 2: `# lang: <code>    baseline: <HEAD commit short hash>`
     - Body rows: `<path>\t<spec-id-list>\t<hash>` (sorted by path). Production files get their 7-char `git hash-object` short hash; test files get `-`. One row per path; if a path covers multiple modules, list them comma-separated (alphabetically sorted).

Use `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh upsert <path> <spec-id> <hash>` to populate rows — it handles sorting and deduplication.

### Update CLAUDE.md

Specflow writes two **independent** marker blocks: a **usage** block (always) and an **optional coding-guidelines** block. Handle each block separately — for each one, read `CLAUDE.md` and:

- Start marker absent → append the block (creating `CLAUDE.md` if it doesn't exist).
- Start marker present → diff against the block below. Different → show the diff and use `AskUserQuestion` to confirm replacement. Identical → skip.

The guidelines block is generic engineering advice, orthogonal to spec-sync; use `AskUserQuestion` to ask whether to include it (default: yes). The user can later delete or hand-edit it without touching the usage block.

**Usage block** (always) — markers `<!-- specflow:start -->` / `<!-- specflow:end -->`:

```markdown
<!-- specflow:start -->
## Specflow

Specs in `specs/` (indexed by `specs/INDEX`) are the reading-guide for committed code.

- **Inspecting behavior**: read the relevant spec first; source is a fallback. For committed code, spec ≡ code.
- **Working on new behavior**: run `/specflow:spec <topic>` to pin down the contract before coding; `/specflow:implement <spec-id>` to build it.
- **After changing code**: run `/specflow:sync` to surface contract drift. Contract-breaking changes route to `/specflow:spec --amend`.
- `INDEX` header records the language for spec bodies; all new specs follow it.
<!-- specflow:end -->
```

**Coding-guidelines block** (optional) — markers `<!-- specflow-guidelines:start -->` / `<!-- specflow-guidelines:end -->`:

```markdown
<!-- specflow-guidelines:start -->
## Coding Guidelines

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.
<!-- specflow-guidelines:end -->
```

### Report

Summary: `specs/INDEX` created with `lang=<code>` and `baseline=<commit>`; N specs written. Suggest `/specflow:spec <topic>` to spec new behavior.
