# Docflow

Keep feature documentation in sync with code — "change code" and "change docs" become two sides of the same action.

## Why

Code evolves continuously; docs don't. Stale docs mislead both humans and LLMs. Docflow ties documentation updates to the coding workflow so they can't fall out of sync.

## Install

```
/plugin marketplace add linfx7/docflow
/plugin install docflow
```

## Commands

### Setup

| Command | Description |
|---------|-------------|
| `/docflow:init` | Initialize docflow in the current project |

### Flow Mode

Structured cycle: brainstorm → plan → implement.

| Command | Description |
|---------|-------------|
| `/docflow:brainstorm` | Divergent exploration of a feature idea — discover, don't decide. Triggers flow state. |
| `/docflow:plan` | Convergent decision-making — grill the user until every detail is nailed down, then create feature docs. Requires flow state. Supports `--amend <feature-id>` for targeted contract updates without a brainstorm. |

### Free Mode

Code first, document later: free → (code freely) → commit.

| Command | Description |
|---------|-------------|
| `/docflow:free` | Enter free-form coding mode — records branch and commit for later diff. Triggers free state. |
| `/docflow:commit` | Detect code changes since free mode started and sync feature documentation. Requires free state. |

### Standalone

| Command | Description |
|---------|-------------|
| `/docflow:implement` | Implement planned features in isolated worktrees. Halts and routes to `plan --amend` on contract drift. |
| `/docflow:sync` | Check consistency between code and feature documentation. Mechanical fixes applied directly; contract drift routed to `plan --amend`. |

## State Management

`.docflow/state` tracks the current mode. Two modes are mutually exclusive:

- **flow**: triggered by `brainstorm`, only `plan` can run (clears on completion)
- **free**: triggered by `free`, only `commit` can run (clears on completion)

When a state is active, all other commands are rejected. Finish the session or delete `.docflow/state` to discard it. The state file also records the branch name to prevent cross-branch corruption.

## Data Model

```
CLAUDE.md                # Appended with docflow constraints
docs/
  INDEX.md               # Feature index (YAML frontmatter)
  features/
    feat-YYMMDD-name.md    # One doc per feature
.docflow/                # Temp directory (gitignored)
```

**INDEX.md** — feature list with IDs, status, and dependencies. No file-level detail.

**Feature doc** — the smallest self-contained unit (readable without other features):

- **Behavioral Contract** — observable behavior, not implementation
- **Key Implementation Notes** — technical choices that affect behavior
- **Associated Files** — production files with git short-hashes for drift detection
- **Tests** — test file paths (no hash; tests evolve alongside behavior)
- **Acceptance Criteria** — testable conditions
- **Change History** — chronological record of updates

Feature lifecycle: `planned` → `active` → `deprecated`. An `active` feature whose contract is rewritten by `/docflow:plan` becomes `amended` until `/docflow:implement` catches the code up.

Feature IDs use `feat-YYMMDD-name` format (e.g., `feat-260430-user-login`). The `feat-` prefix marks the ID as a feature. Name is a slug: lowercase letters, digits, hyphens.

## Contract Ownership

`## Behavioral Contract` is the feature's design decision and has a strict write-permission matrix:

| Command | May write Behavioral Contract? |
|---------|-------------------------------|
| `plan` (flow / amend) | yes, after grill-me decisions |
| `commit` | yes, after user confirmation |
| `implement` | no — STOP and route to `plan --amend` |
| `sync` | no — STOP and route to `plan --amend` |

This keeps contracts as human-reviewed design, never silently inferred from code diffs.

## Plugin Structure

```
docflow/
  .claude-plugin/
    plugin.json
    marketplace.json
  commands/
    init.md, brainstorm.md, plan.md, implement.md
    free.md, commit.md, sync.md
  references/
    feature-template.md    # Shared by init, plan, commit, sync
    conventions.md         # Feature IDs, file hash, Associated Files format, INDEX schema, Change History format, contract rules
```

## Design Principles

- Feature docs are the source of truth for behavioral contracts
- One feature = one self-contained unit
- Flow and free modes are mutually exclusive
- All command prompts in English; user interaction follows user's language
- All commands set `disable-model-invocation: true` — user-invoked only

## Acknowledgements

- `/docflow:plan` adopts the interview technique from [grill-me](https://github.com/mattpocock/skills) by Matt Pocock
- Coding guidelines in CLAUDE.md are adapted from [andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) by Jiayuan Zhang
