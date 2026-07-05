---
description: Set token-optimizer filtering aggressiveness (strict | normal | off)
argument-hint: strict|normal|off
allowed-tools: Bash(cat:*), Bash(jq:*), Bash(mkdir:*), Bash(mv:*), Bash(echo:*)
---

## Your task

Set the token-optimizer budget mode to: **$ARGUMENTS**

1. Validate the argument. It must be exactly one of `strict`, `normal`, or `off`:
   - `strict` — halves the output-line limit, caps grep results at 30, trims files over 200 lines.
   - `normal` — the defaults (150-line output limit, 400-line file threshold).
   - `off` — hooks pass everything through untouched (counters keep their values).
   If the argument is missing or invalid, report the current mode from the state file and list the three valid values. Do not change anything.

2. If valid, update the state file at `${CLAUDE_PROJECT_DIR:-.}/.claude/token-optimizer-state.json` (create the `.claude` directory and file if missing), setting the `budget` key while preserving all other keys:

```bash
STATE="${CLAUDE_PROJECT_DIR:-.}/.claude/token-optimizer-state.json"
mkdir -p "$(dirname "$STATE")"
cat "$STATE" 2>/dev/null | jq --arg b "MODE" '. + {budget: $b}' > "$STATE.tmp" 2>/dev/null || echo "{\"budget\":\"MODE\"}" > "$STATE.tmp"
mv "$STATE.tmp" "$STATE"
```

(replace `MODE` with the validated value)

3. Confirm the new mode in one sentence. The hooks read the state file on every call, so the change takes effect immediately — no restart needed.
