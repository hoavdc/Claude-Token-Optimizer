#!/usr/bin/env bash
# token-optimizer: Stop hook.
# Counts conversation turns in the per-project state file and, every
# compactReminderTurns turns (default 12), emits a systemMessage reminding the
# user to run /compact. Never blocks: emits no "decision" field, ever.
#
# SAFETY: any error -> exit 0 silently.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" 2>/dev/null || exit 0

# shellcheck disable=SC2034  # INPUT is read by lib.sh helpers
INPUT="$(cat 2>/dev/null)" || exit 0
[ "$TO_HAS_JQ" = 1 ] || [ "$TO_HAS_PY" = 1 ] || exit 0

# If a Stop hook already forced a continuation, stay out of the way.
[ "$(json_get stop_hook_active)" = "true" ] && exit 0

TURNS="$(state_get turns 0)"
[[ "$TURNS" =~ ^[0-9]+$ ]] || TURNS=0
TURNS=$((TURNS + 1))
state_update "turns=$TURNS" >/dev/null 2>&1

REMIND="$(num_opt compactReminderTurns 12)"
[ "$REMIND" -lt 2 ] && REMIND=2

if [ $((TURNS % REMIND)) -eq 0 ]; then
  cat <<EOF
{"systemMessage": "token-optimizer: $TURNS turns in this session. Consider running /compact now, before auto-compact picks for you. Keep: the current task, files being edited, settled architecture decisions. Drop: stale tool output, exploratory dead ends, failed attempts. (Interval configurable via the compactReminderTurns setting.)"}
EOF
fi
exit 0
