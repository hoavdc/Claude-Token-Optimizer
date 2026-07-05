---
description: Report token-optimizer session stats - turns since last compact, hook activity, and rough estimated savings
allowed-tools: Bash(cat:*), Bash(jq:*), Bash(echo:*)
---

## Current state

- State file: !`cat "${CLAUDE_PROJECT_DIR:-.}/.claude/token-optimizer-state.json" 2>/dev/null || echo '{}'`

## Your task

Report the token-optimizer status from the state JSON above, as a short table or list:

1. **Turns since session start / last compact**: the `turns` field (0 or missing means a fresh session).
2. **Commands rewritten**: the `rewrites` counter (PreToolUse hook made a command leaner).
3. **Outputs truncated**: the `truncations` counter and `elided_lines` total (PostToolUse hook compressed Bash output).
4. **Estimated tokens saved**: `elided_lines × ~10 tokens/line`. Label this clearly as a **rough estimate** — actual savings depend on line length and content.
5. **Current budget mode**: the `budget` field (`strict`, `normal`, or `off`; default `normal`). Mention it can be changed with `/token-optimizer:budget`.

If the state file is empty or missing, say the plugin hasn't recorded activity in this project yet (hooks run on Bash tool calls, and the state file is created on session start).

Keep the report under 10 lines. Do not read any other files.
