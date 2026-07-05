---
name: token-discipline
description: Token-efficiency rules for working in a codebase. Apply in every coding session when reading files, running commands, or deciding whether to delegate work to subagents.
---

# Token discipline

Context tokens are the scarcest resource in a coding session. Apply these rules continuously:

1. **Read only what's needed.** Locate the relevant code with Grep first, then Read with `offset`/`limit` to load only that section. Never read a whole file when a 50-line range answers the question, and never re-read a file that hasn't changed.

2. **Never echo long code blocks back** in responses unless the user explicitly asks. Reference code as `file:line` instead.

3. **Filter at the source.** Before running any command with large output, ask "which fields do I actually need?" and put the filter inside the command itself: `jq '.field'` for JSON, `git diff --stat`, `git log --oneline -20`, `grep ... | head -50`, `--silent`/`-q` flags on package managers.

4. **Delegate to the cheap subagents** whenever a task matches their descriptions: `token-optimizer:quick-reader` for understanding files/directories, `token-optimizer:quick-reviewer` for small diffs, simple unit tests, and lint runs, `token-optimizer:doc-writer` for docstrings, comments, READMEs, and changelogs. The main model should only do work that requires its judgment.

5. **Suggest `/compact` proactively** when the conversation grows long (many turns, lots of stale tool output), rather than waiting for auto-compact to fire at an arbitrary point. Recommend keeping the current task, files being edited, and settled decisions; dropping stale output and failed attempts.

6. **Protect the prompt cache.** Keep the conversation prefix stable: do not suggest editing CLAUDE.md, system context, or session-level configuration mid-session unless truly necessary — any change to the stable prefix invalidates prompt caching and re-bills the entire context.
