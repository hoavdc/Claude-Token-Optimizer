#!/usr/bin/env bash
# token-optimizer: SessionStart hook.
# Resets the per-session turn counter and injects a short additionalContext
# block (<120 words) with token-discipline rules. Runs once per session start
# or resume, so it never disturbs the stable prompt prefix mid-session
# (protects prompt caching).
#
# SAFETY: any error -> exit 0 silently.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" 2>/dev/null || exit 0

# shellcheck disable=SC2034  # INPUT is read by lib.sh helpers
INPUT="$(cat 2>/dev/null)" || exit 0

if [ "$TO_HAS_JQ" = 1 ] || [ "$TO_HAS_PY" = 1 ]; then
  state_update turns=0 "session_started=$(date +%s 2>/dev/null || echo 0)" >/dev/null 2>&1
fi

cat <<'EOF'
{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "token-optimizer active. Conserve context tokens: (1) locate code with Grep/Glob first, then Read only the relevant range via offset/limit — avoid whole-file reads; (2) never re-read files that have not changed; (3) do not repeat file contents back in responses; (4) prefer Grep/Glob tools over raw bash find/grep; (5) delegate simple work to cheap subagents — token-optimizer:quick-reader (summarize files/dirs), token-optimizer:quick-reviewer (small reviews, simple unit tests, lint), token-optimizer:doc-writer (docstrings, comments, READMEs, changelogs); (6) filter command output at the source (jq for JSON fields, git --stat, head/grep) instead of ingesting everything."}}
EOF
exit 0
