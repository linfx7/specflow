---
description: Grill the user on a new behavior, then write the spec; or amend existing specs in place
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion]
argument-hint: [topic hint | --amend <spec-id> [spec-id ...]]
---

Two modes. Default is **new** — grill the user, write one or more new specs. **Amend** (`--amend <spec-id> [spec-id ...]`) updates existing specs in place.

## Pre-check

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/precheck.sh initialized`. Non-zero → STOP and print stderr verbatim.

Read the INDEX header `lang` via `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh header lang`. All prompts and generated spec text use this language. Mirror the user if they switch mid-conversation, but written spec bodies stay in the configured language for consistency.

## Mode selection

- Arguments contain `--amend` → **Amend** mode.
- Otherwise → **New** mode. The remaining arguments (if any) are a topic hint.

---

## New mode

### Explore before asking

Read `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` (via `cat`) and `specs/INDEX`. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh list-by-path <path>` for each file that the topic plausibly touches; load those specs read-only for context.

### Grill the user

Interview the user relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

Cover every boundary before proposing a split: inputs, outputs, errors, edge cases, acceptance tests, dependencies. Do NOT proceed until every open question is resolved.

If the user expresses intent to abandon, use `AskUserQuestion`: (a) discard any partial drafts, (b) save drafts somewhere the user picks. Then STOP. No hidden state left behind.

### Propose the split

Propose one or more specs. For each:

- NEW vs UPDATE (an UPDATE is an absorbed existing spec — see overlap check below)
- ID via `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh next-id` (NEW) or the existing id (UPDATE)
- Name (short human-readable title)
- Status: `draft` for NEW; `amended` for UPDATE whose contract changes
- `## Behavioral Contract` — concise, observable, one bullet per rule
- `## Acceptance Criteria` — testable checkboxes
- `## Edge Cases` — only non-obvious behaviors
- `deps` — other spec IDs this one depends on

Keep Behavioral Contract + Acceptance Criteria ≤ 40 lines combined.

Present the summary; use `AskUserQuestion` to let the user adjust.

### Overlap check

For each file the proposed work plausibly touches, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/index.sh list-by-path <path>` to find other specs covering it. Apply contract classification (see `${CLAUDE_PLUGIN_ROOT}/references/conventions.md`):

- **Contract-breaking for an existing spec** → absorb that spec into the bundle. Grill the user on the new contract for it, update its `## Behavioral Contract` / `## Acceptance Criteria` / `## Change History`, flip its status from `active` → `amended`. Record `- <YYYY-MM-DD>: [contract] absorbed into <spec-id>` on the absorbed spec's Change History (where `<spec-id>` is the driving spec). Implemented together by passing the driving spec's ID to `/specflow:implement`.
- **Hash-only** → no spec edit. INDEX hashes refresh during `implement`.

### Write specs

For each NEW spec: create `specs/spec-NNN-name.md` from `${CLAUDE_PLUGIN_ROOT}/references/spec-template.md`. Fill in frontmatter (`status: draft`), Behavioral Contract, Acceptance Criteria, Edge Cases (only if non-obvious), and seed Change History with `- <YYYY-MM-DD>: Initial spec.`

For each UPDATE (absorbed existing spec): edit the spec file in place. Update affected sections; append a Change History entry.

Do **not** touch `specs/INDEX` here. NEW specs have no files yet; INDEX gets populated when `implement` runs. UPDATE specs already have INDEX rows — the hash refresh happens at `implement` time too.

### Report

List all specs in the bundle with their statuses. Suggest `/specflow:implement <spec-id>` (the bundle is expanded from the driving spec).

---

## Amend mode (`--amend <id> [id ...]`)

### Load

Read each spec file and `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` (via `cat`). No codebase exploration beyond what the specs themselves reference.

### Grill

For each spec, interview the user relentlessly about every aspect of the contract change until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

Cover what's changing, why, and which acceptance criteria are affected.

### Update

For each spec:

- Rewrite affected `## Behavioral Contract` bullets.
- Update `## Acceptance Criteria` to match. Unchecking a criterion that was previously checked is fine — implementation hasn't caught up yet.
- Append Change History: `- <YYYY-MM-DD>: [contract] <one-line summary>`.
- Flip `status`: `active` → `amended`. `draft` stays `draft`. Other statuses → ask.

No INDEX writes. No hash refreshes. `implement` will reconcile when the code catches up.

### Report

List amended spec IDs. Suggest `/specflow:implement <spec-id>` for each (one at a time) to catch the code up to the new contract.
