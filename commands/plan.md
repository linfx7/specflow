---
description: Convergent decision-making — grill the user until every detail is nailed down, then create feature docs
disable-model-invocation: true
allowed-tools: [Read, Write, Glob, Grep, Bash, AskUserQuestion]
argument-hint: [brainstorm-filename | --amend <feature-id> [feature-id ...]]
---

Two modes: **flow** (normal, consumes brainstorm) and **amend** (targeted updates to existing features, no brainstorm needed).

## Pre-check

1. Determine mode from invocation:
   - **Flow**: no `--amend` argument. Run `bash scripts/precheck.sh flow-active`. Non-zero exit → STOP and print the script's stderr verbatim.
   - **Amend**: `--amend <feature-id>` or a list of feature IDs was provided. Run `bash scripts/precheck.sh no-state`. Non-zero exit → STOP and print the script's stderr verbatim.

## Steps

### Decide

**Flow**: read the brainstorm file (from argument or `brainstormFile` in state), `docs/INDEX.md`, and feature docs relevant to the brainstorm topic. Missing brainstorm file → STOP: "Brainstorm file not found: <path>. Delete `.docflow/state` and re-run `/docflow:brainstorm`."

**Amend**: read `docs/INDEX.md` and the feature docs for the specified `--amend` feature IDs.

Interview the user relentlessly about every open question until reaching shared understanding. One question at a time, with a recommended answer. Explore the codebase rather than asking questions you can answer yourself.

Do NOT proceed until every open question is resolved. If the user expresses intent to abandon, use `AskUserQuestion`: (a) discard (delete state + brainstorm file), (b) pause (keep files). Then STOP.

### Split into features

Read `references/conventions.md`. Propose a feature split. For each feature:
- NEW vs UPDATE
- Feature ID (`feat-YYMMDD-name` format)
- Scope: behavioral contracts it covers
- Dependencies
- Acceptance criteria
- **Test plan**: test files + one-line assertion summary each. Test files go into `## Tests` (paths only, no hash — they evolve alongside behavior).

`## Associated Files` for NEW features stays empty until `implement` populates it from the committed diff (see conventions).

Present the summary. Use `AskUserQuestion` to let the user adjust.

### Impact analysis

For each feature in the split, identify files it will touch (declared `## Associated Files` for UPDATEs, plus files implied by new Key Implementation Notes).

`Grep` the touch list against all other feature docs' `## Associated Files`. For each match, apply contract classification (see conventions):

- **Contract-breaking**: absorb into the bundle. Update its `## Behavioral Contract` and `## Acceptance Criteria` now — grill the user until every contract-breaking change has a resolved updated contract. These features share a change history entry (see conventions) referencing the driving feature.
- **Hash-only**: no doc change in plan. Implement will mechanically refresh hashes.

### Write docs

For each feature in the final bundle:
- **New**: create `docs/features/<feat-YYMMDD-name>.md` from `references/feature-template.md`.
- **Updated** (driving or absorbed): verify the file has all sections from `references/feature-template.md` — add any missing. Update affected sections with newly decided contracts, test plan, and criteria. Add a change history entry (see conventions).

Update `docs/INDEX.md`: add new features (status `planned`); for contract-breaking absorbed features, set status to `amended` if currently `active`, otherwise leave as-is (a `planned` feature stays `planned`). Update dependencies.

### Clean up

**Flow**: delete `.docflow/state`. Use `AskUserQuestion` to ask whether to delete the consumed brainstorm file.

**Amend**: nothing to clean up.

List all features with status `planned` or `amended`, and suggest `/docflow:implement`.
