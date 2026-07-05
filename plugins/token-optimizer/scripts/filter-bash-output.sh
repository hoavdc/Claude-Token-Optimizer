#!/usr/bin/env bash
# token-optimizer: PostToolUse(Bash) hook.
# Compresses oversized Bash stdout before it enters Claude's context, via
# hookSpecificOutput.updatedToolOutput (must mirror the Bash tool's output
# shape: {stdout, stderr, interrupted, isImage}). The command has already run;
# only what Claude sees is changed.
#
# SAFETY: any error or unexpected shape -> exit 0, original output untouched.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" 2>/dev/null || exit 0

INPUT="$(cat 2>/dev/null)" || exit 0
[ -z "$INPUT" ] && exit 0
[ "$TO_HAS_JQ" = 1 ] || [ "$TO_HAS_PY" = 1 ] || exit 0

BUDGET="$(budget)"
[ "$BUDGET" = "off" ] && exit 0

MAX="$(num_opt maxToolOutputLines 150)"
[ "$BUDGET" = "strict" ] && MAX=$((MAX / 2))
[ "$MAX" -lt 20 ] && MAX=20

STDOUT="$(json_get tool_response.stdout)"
IS_STRING=0
if [ -z "$STDOUT" ]; then
  # Some tool responses are plain strings rather than {stdout,...} objects.
  STDOUT="$(json_get tool_response)"
  IS_STRING=1
fi
[ -z "$STDOUT" ] && exit 0

TOTAL=$(printf '%s\n' "$STDOUT" | wc -l | tr -d ' ')
[[ "$TOTAL" =~ ^[0-9]+$ ]] || exit 0
[ "$TOTAL" -le "$MAX" ] && exit 0

TMP="$(mktemp 2>/dev/null)" || exit 0
trap 'rm -f "$TMP" "$TMP.f" 2>/dev/null' EXIT
printf '%s\n' "$STDOUT" > "$TMP"

MSG=""
KIND="default"
if grep -q 'Traceback (most recent call last)' "$TMP" 2>/dev/null \
  || grep -qE '^[[:space:]]+at .+\(.+:[0-9]+' "$TMP" 2>/dev/null; then
  KIND="trace"
elif grep -qEc '(^|[[:space:]])(PASS|FAIL|ERROR|✓|✗|ok [0-9]|not ok|passing|failing|Compiling|Building|Bundling)' "$TMP" 2>/dev/null \
  && [ "$(grep -cE '(^|[[:space:]])(PASS|FAIL|ERROR|✓|✗|ok [0-9]|not ok|passing|failing|Compiling|Building|Bundling)' "$TMP" 2>/dev/null)" -gt 3 ]; then
  KIND="buildlog"
fi

FIRST_CHAR="$(head -c 200 "$TMP" | tr -d '[:space:]' | head -c 1)"
if [ "$FIRST_CHAR" = "{" ] || [ "$FIRST_CHAR" = "[" ]; then
  MSG="token-optimizer: that command returned $TOTAL lines of JSON. Next time pipe it through jq to extract only the fields you need (e.g. ... | jq '.items[].name')."
fi

case "$KIND" in
  trace)
    # Real error usually lives at the end of a stack trace.
    { head -5 "$TMP"
      echo "[... $((TOTAL - 20)) lines elided (stack trace) — rerun with a specific filter if needed ...]"
      tail -15 "$TMP"; } > "$TMP.f"
    ;;
  buildlog)
    # Drop progress noise and repeated warnings; keep errors/failures + tail summary.
    awk '
      /^[[:space:]]*(\[[0-9]+\/[0-9]+\]|[0-9]+%|[.#=>-]{4,}[[:space:]]*$)/ { next }
      /^(npm |)([Ww][Aa][Rr][Nn]|warning[: ])/ { if (++warn[$0] > 1) next }
      { print }
    ' "$TMP" > "$TMP.f" 2>/dev/null || cp "$TMP" "$TMP.f"
    KEPT=$(wc -l < "$TMP.f" | tr -d ' ')
    if [ "$KEPT" -gt "$MAX" ]; then
      H=$((MAX * 3 / 5)); T=$((MAX / 4))
      { head -"$H" "$TMP.f"
        echo "[... $((KEPT - H - T)) lines elided (build/test noise) — rerun with a specific filter if needed ...]"
        tail -"$T" "$TMP.f"; } > "$TMP.f2" && mv "$TMP.f2" "$TMP.f"
    fi
    ;;
  *)
    H=$((MAX * 3 / 5)); T=$((MAX / 4))
    { head -"$H" "$TMP"
      echo "[... $((TOTAL - H - T)) lines elided — rerun with a specific filter if needed ...]"
      tail -"$T" "$TMP"; } > "$TMP.f"
    ;;
esac

[ -s "$TMP.f" ] || exit 0
NEW_TOTAL=$(wc -l < "$TMP.f" | tr -d ' ')
[ "$NEW_TOTAL" -ge "$TOTAL" ] && exit 0
ELIDED=$((TOTAL - NEW_TOTAL))

# ---- emit updatedToolOutput ---------------------------------------------------
if [ "$TO_HAS_JQ" = 1 ]; then
  if [ "$IS_STRING" = 1 ]; then
    OUT="$(jq -c -n --rawfile s "$TMP.f" --arg m "$MSG" '
      {hookSpecificOutput: {hookEventName: "PostToolUse", updatedToolOutput: $s}}
      + (if $m == "" then {} else {systemMessage: $m} end)' 2>/dev/null)" || exit 0
  else
    OUT="$(printf '%s' "$INPUT" | jq -c --rawfile s "$TMP.f" --arg m "$MSG" '
      {hookSpecificOutput: {hookEventName: "PostToolUse",
        updatedToolOutput: (.tool_response + {stdout: $s})}}
      + (if $m == "" then {} else {systemMessage: $m} end)' 2>/dev/null)" || exit 0
  fi
else
  OUT="$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    new = open(sys.argv[1]).read()
    tr = d.get("tool_response")
    upd = new if not isinstance(tr, dict) else {**tr, "stdout": new}
    out = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "updatedToolOutput": upd}}
    if sys.argv[2]:
        out["systemMessage"] = sys.argv[2]
    print(json.dumps(out))
except Exception:
    pass' "$TMP.f" "$MSG" 2>/dev/null)" || exit 0
fi
[ -z "$OUT" ] && exit 0

state_update truncations+=1 "elided_lines+=$ELIDED" >/dev/null 2>&1
printf '%s\n' "$OUT"
exit 0
