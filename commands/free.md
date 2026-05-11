---
description: Enter free-form coding mode — records branch and commit for later diff
disable-model-invocation: true
allowed-tools: [Read, Bash, Write, Glob, Grep]
---

## Pre-check

Run `bash scripts/precheck.sh no-state`. Non-zero exit → STOP and print the script's stderr verbatim.

## Steps

Run `git branch --show-current` and `git rev-parse HEAD`. Write `.docflow/state`:
```
mode=free
branch=<current branch name>
commitId=<HEAD commit hash>
```

Tell the user free mode is active — state is on disk, so `/clear` or context compaction won't affect it. They can code across multiple windows/sessions, then run `/docflow:commit` when done.
