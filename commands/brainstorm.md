---
description: Divergent exploration of a feature idea — discover, don't decide
disable-model-invocation: true
allowed-tools: [Read, Glob, Grep, Bash, AskUserQuestion, Write]
---

## Pre-check

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/precheck.sh no-state`. Non-zero exit → STOP and print the script's stderr verbatim.

## Steps

### Explore

Ask open-ended questions to map:
- The problem and why it matters now
- What success looks like from the user's perspective
- Related code or patterns already in the codebase
- Technical constraints and dependencies
- Possible approaches — without committing to one

If a question can be answered by exploring the codebase, explore instead of asking.

Keep the conversation divergent. When the user narrows down prematurely, ask "what else could this be?" Surface unknowns rather than resolving them.

### Write brainstorm

Once the problem space is well-mapped and key unknowns surfaced, write `.docflow/brainstorm-<yyyyMMdd-HHmmss>.md`:

```markdown
# Brainstorm: <title>

## Context
<background, motivation, why this matters>

## Discoveries
- <facts found in code, existing patterns, technical constraints>

## Related Existing Features
- <features from docs/INDEX.md this idea touches, or "None">

## Ideas & Possibilities
- <functional options explored, no commitment>

## Open Questions
- <decisions to be made in plan phase>
```

### Create state

Write `.docflow/state`:
```
mode=flow
branch=<current branch from git branch --show-current>
brainstormFile=.docflow/brainstorm-<yyyyMMdd-HHmmss>.md
```

Suggest `/docflow:plan` to make decisions and create feature docs.
