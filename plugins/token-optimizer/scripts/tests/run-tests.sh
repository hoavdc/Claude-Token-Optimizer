#!/usr/bin/env bash
# Offline tests for token-optimizer hook scripts.
# Usage: bash scripts/tests/run-tests.sh   (from the plugin root or anywhere)
# Requires: bash, jq. No Claude Code needed.
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$TESTS_DIR")"
FIX="$TESTS_DIR/fixtures"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq is required to run the test suite"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export CLAUDE_PROJECT_DIR="$WORK"
unset CLAUDE_PLUGIN_OPTION_maxToolOutputLines CLAUDE_PLUGIN_OPTION_compactReminderTurns CLAUDE_PLUGIN_OPTION_aggressiveMode 2>/dev/null || true

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

run() { # run <script> <fixture-file-or-'-'> ; stdin from $3 if given as string
  bash "$SCRIPTS_DIR/$1" < "$2"
}

check_exit0() { # every script must exit 0 on every input
  local rc=$1 name=$2
  [ "$rc" -eq 0 ] && ok "$name exits 0" || bad "$name exited $rc (must NEVER be non-zero)"
}

echo "== rewrite-verbose-cmd.sh =="

OUT=$(run rewrite-verbose-cmd.sh "$FIX/pre-git-status.json"); RC=$?
check_exit0 $RC "git status"
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.updatedInput.command == "git status --short --branch"' >/dev/null 2>&1; then
  ok "git status rewritten to --short --branch"
else
  bad "git status not rewritten correctly; got: $OUT"
fi
printf '%s' "$OUT" | jq -e '.hookSpecificOutput | has("permissionDecision") | not' >/dev/null 2>&1 \
  && ok "no permissionDecision emitted (nothing auto-approved)" \
  || bad "permissionDecision leaked into output"

OUT=$(run rewrite-verbose-cmd.sh "$FIX/pre-piped.json"); RC=$?
check_exit0 $RC "piped command"
[ -z "$OUT" ] && ok "piped/redirected command passed through untouched" || bad "piped command was modified: $OUT"

OUT=$(run rewrite-verbose-cmd.sh "$FIX/pre-destructive.json"); RC=$?
check_exit0 $RC "rm -rf"
[ -z "$OUT" ] && ok "destructive command passed through untouched" || bad "rm -rf was modified: $OUT"

OUT=$(run rewrite-verbose-cmd.sh "$FIX/pre-grep-r.json"); RC=$?
check_exit0 $RC "grep -r"
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.updatedInput.command == "grep -r TODO src | head -50"' >/dev/null 2>&1; then
  ok "grep -r capped with | head -50"
else
  bad "grep -r not capped; got: $OUT"
fi

OUT=$(echo 'this is not json {' | bash "$SCRIPTS_DIR/rewrite-verbose-cmd.sh"); RC=$?
check_exit0 $RC "malformed input"
[ -z "$OUT" ] && ok "malformed JSON input -> silent pass-through" || bad "malformed input produced output: $OUT"

echo "== filter-bash-output.sh =="

OUT=$(run filter-bash-output.sh "$FIX/post-small.json"); RC=$?
check_exit0 $RC "small output"
[ -z "$OUT" ] && ok "output under limit passed through untouched" || bad "small output was modified: $OUT"

# 400-line output (limit defaults to 150) -> must be truncated with a marker
BIG=$(jq -n '{session_id:"t", hook_event_name:"PostToolUse", cwd:"/tmp", tool_name:"Bash",
  tool_input:{command:"seq 400"},
  tool_response:{stdout:([range(1;401)] | map("line \(.)") | join("\n")), stderr:"", interrupted:false, isImage:false}}')
OUT=$(printf '%s' "$BIG" | bash "$SCRIPTS_DIR/filter-bash-output.sh"); RC=$?
check_exit0 $RC "long output"
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.updatedToolOutput.stdout | contains("lines elided")' >/dev/null 2>&1; then
  ok "long output truncated with elided marker"
else
  bad "long output not truncated; got: $(printf '%s' "$OUT" | head -c 200)"
fi
NEWLINES=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedToolOutput.stdout' | wc -l | tr -d ' ')
[ "$NEWLINES" -lt 200 ] && ok "truncated output is $NEWLINES lines (< 200)" || bad "truncated output still $NEWLINES lines"
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.updatedToolOutput | (has("stderr") and has("interrupted") and has("isImage"))' >/dev/null 2>&1 \
  && ok "updatedToolOutput preserves Bash output shape" \
  || bad "updatedToolOutput shape mismatch (would be ignored by Claude Code)"

# Python stack trace -> head 5 + tail 15
TRACE=$(jq -n '{session_id:"t", hook_event_name:"PostToolUse", cwd:"/tmp", tool_name:"Bash",
  tool_input:{command:"python app.py"},
  tool_response:{stdout:("Traceback (most recent call last):\n" + ([range(0;300)] | map("  File \"m\(.).py\", line \(.), in f\(.)") | join("\n")) + "\nValueError: boom"), stderr:"", interrupted:false, isImage:false}}')
OUT=$(printf '%s' "$TRACE" | bash "$SCRIPTS_DIR/filter-bash-output.sh"); RC=$?
check_exit0 $RC "stack trace"
if printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedToolOutput.stdout' 2>/dev/null | grep -q "ValueError: boom"; then
  ok "stack trace keeps the final error line"
else
  bad "stack trace lost the error line"
fi

echo "== context-meter.sh =="

rm -f "$WORK/.claude/token-optimizer-state.json"
OUT=$(run context-meter.sh "$FIX/stop-basic.json"); RC=$?
check_exit0 $RC "first turn"
[ -z "$OUT" ] && ok "turn 1: no reminder" || bad "turn 1 produced output: $OUT"
[ "$(jq -r '.turns' "$WORK/.claude/token-optimizer-state.json" 2>/dev/null)" = "1" ] \
  && ok "turn counter incremented to 1" || bad "turn counter not written"

for _ in $(seq 2 11); do run context-meter.sh "$FIX/stop-basic.json" >/dev/null; done
OUT=$(run context-meter.sh "$FIX/stop-basic.json"); RC=$?
check_exit0 $RC "12th turn"
if printf '%s' "$OUT" | jq -e '.systemMessage | contains("/compact")' >/dev/null 2>&1; then
  ok "turn 12: /compact reminder emitted"
else
  bad "turn 12: no reminder; got: $OUT"
fi
printf '%s' "$OUT" | jq -e 'has("decision") | not' >/dev/null 2>&1 \
  && ok "reminder never blocks (no decision field)" || bad "reminder contains a decision field"

OUT=$(run context-meter.sh "$FIX/stop-active.json"); RC=$?
check_exit0 $RC "stop_hook_active"
[ -z "$OUT" ] && ok "stop_hook_active=true -> silent exit" || bad "stop_hook_active produced output: $OUT"

echo "== session-init.sh =="

OUT=$(run session-init.sh "$FIX/session-start.json"); RC=$?
check_exit0 $RC "session start"
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | length > 0)' >/dev/null 2>&1; then
  ok "SessionStart injects additionalContext"
else
  bad "SessionStart output invalid: $OUT"
fi
WORDS=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' | wc -w | tr -d ' ')
[ "$WORDS" -lt 120 ] && ok "additionalContext is $WORDS words (< 120)" || bad "additionalContext too long: $WORDS words"
[ "$(jq -r '.turns' "$WORK/.claude/token-optimizer-state.json" 2>/dev/null)" = "0" ] \
  && ok "turn counter reset to 0" || bad "turn counter not reset"

echo "== budget mode =="

echo '{"budget":"off"}' > "$WORK/.claude/token-optimizer-state.json"
OUT=$(run rewrite-verbose-cmd.sh "$FIX/pre-git-status.json"); RC=$?
check_exit0 $RC "budget off (pre)"
[ -z "$OUT" ] && ok "budget=off disables command rewriting" || bad "budget=off still rewrote: $OUT"
OUT=$(printf '%s' "$BIG" | bash "$SCRIPTS_DIR/filter-bash-output.sh"); RC=$?
check_exit0 $RC "budget off (post)"
[ -z "$OUT" ] && ok "budget=off disables output filtering" || bad "budget=off still filtered"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
