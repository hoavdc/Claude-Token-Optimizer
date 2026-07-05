#!/usr/bin/env bash
# token-optimizer: PreToolUse(Bash) hook.
# Rewrites well-known token-hungry commands into leaner equivalents via
# hookSpecificOutput.updatedInput. Normal permission evaluation still applies
# (no permissionDecision is emitted, so nothing gets auto-approved).
#
# SAFETY: on any parse error, unknown shape, complex pipeline, heredoc, or
# write/delete command, exit 0 with no output -> command runs untouched.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" 2>/dev/null || exit 0

INPUT="$(cat 2>/dev/null)" || exit 0
[ -z "$INPUT" ] && exit 0
[ "$TO_HAS_JQ" = 1 ] || [ "$TO_HAS_PY" = 1 ] || exit 0

CMD="$(json_get tool_input.command)" || exit 0
[ -z "$CMD" ] && exit 0

BUDGET="$(budget)"
[ "$BUDGET" = "off" ] && exit 0

# ---- safety gates: never touch complex or mutating commands -----------------
case "$CMD" in
  *$'\n'*) exit 0 ;;                                  # multi-line / heredoc body
  *'<<'* | *'|'* | *';'* | *'&&'*) exit 0 ;;          # pipes, chains, heredocs
  *'>'* | *'<'* | *'`'* | *'$('*) exit 0 ;;           # redirects, substitution
esac
case "$CMD" in
  rm\ * | mv\ * | cp\ * | dd\ * | sudo\ * | git\ push* | git\ commit* | \
  git\ reset* | git\ checkout* | git\ rebase* | git\ clean* | chmod\ * | chown\ *)
    exit 0 ;;
esac

HOOK_CWD="$(json_get cwd)"
[ -z "$HOOK_CWD" ] && HOOK_CWD="."

NEW=""
MSG=""

# ---- rewrite table (first match wins) ----------------------------------------
if [ "$CMD" = "git status" ]; then
  NEW="git status --short --branch"

elif [[ "$CMD" =~ ^git\ log($|\ ) ]] \
  && ! [[ "$CMD" =~ (--oneline|--max-count|--pretty|--format|--stat|-n\ ?[0-9]|\ -[0-9]+|\ -p($|\ )) ]] \
  && ! [[ "$CMD" =~ (--grep|--author|--since|--until|--all-match|\ -S|\ -G|\ -L) ]]; then
  # (searches like --grep/--author are left alone: capping them at 20 could
  # hide exactly the commits Claude is looking for)
  NEW="$CMD --oneline -20"

elif [ "$CMD" = "git diff" ]; then
  NEW="git diff --stat"
  MSG="token-optimizer: rewrote unbounded 'git diff' to '--stat'. Ask for 'git diff -- <file>' when you need a specific file's changes."

elif [[ "$CMD" =~ ^ls\ -(la|al|l|lah|alh)($|\ ([^\ ]+)$) ]]; then
  DIR="${BASH_REMATCH[3]:-.}"
  case "$DIR" in [!/]*) ABS="$HOOK_CWD/$DIR" ;; *) ABS="$DIR" ;; esac
  COUNT=$(ls -1 "$ABS" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -gt 50 ]; then
    if [ "$DIR" = "." ]; then NEW="ls -1"; else NEW="ls -1 $DIR"; fi
    MSG="token-optimizer: directory has $COUNT entries; long listing replaced with names only. Rerun 'ls -l <specific-file>' if you need metadata."
  fi

elif [[ "$CMD" =~ ^find($|\ ) ]] \
  && ! [[ "$CMD" =~ -maxdepth|-delete|-exec|-prune|-depth|!|\( ]]; then
  # (! and \( start expression groups; inserting -maxdepth near them could
  # change what gets negated/grouped, so those commands pass through)
  if [[ "$CMD" =~ ^(find(\ [^-][^\ ]*)*)(\ -.*)?$ ]]; then
    PREFIX="${BASH_REMATCH[1]}"
    REST="${BASH_REMATCH[3]}"
    NEW="$PREFIX -maxdepth 4$REST"
    MSG="token-optimizer: added '-maxdepth 4' to find. Increase it explicitly if you truly need a deeper walk."
  fi

elif [[ "$CMD" =~ ^cat\ ([^-][^\ ]*)$ ]]; then
  FILE="${BASH_REMATCH[1]}"
  case "$FILE" in [!/]*) ABS="$HOOK_CWD/$FILE" ;; *) ABS="$FILE" ;; esac
  THRESHOLD=400
  [ "$BUDGET" = "strict" ] && THRESHOLD=200
  LINES=$(wc -l < "$ABS" 2>/dev/null | tr -d ' ')
  if [[ "$LINES" =~ ^[0-9]+$ ]] && [ "$LINES" -gt "$THRESHOLD" ]; then
    NEW="head -200 $FILE"
    MSG="token-optimizer: $FILE is $LINES lines long; showing the first 200. Use the Read tool's offset/limit to read only the relevant section."
  fi

elif [[ "$CMD" =~ ^npm\ (install|i|ci)($|\ ) ]] \
  && ! [[ "$CMD" =~ --silent|--quiet|--verbose|--loglevel|--json|\ -s($|\ )|\ -q($|\ )|\ -d+($|\ ) ]]; then
  # (explicit --verbose/--loglevel means the user WANTS the output; don't fight it)
  NEW="$CMD --silent"

elif [[ "$CMD" =~ ^pip3?\ install\  ]] \
  && ! [[ "$CMD" =~ --quiet|--verbose|\ -q($|\ )|\ -v+($|\ ) ]]; then
  NEW="$CMD -q"

elif [[ "$CMD" =~ ^grep\  ]] && [[ "$CMD" =~ \ -[a-zA-Z]*r ]] \
  && ! [[ "$CMD" =~ \ -[a-zA-Z]*(l|c)($|\ )|\ -m\ ?[0-9]|--max-count|--files-with-matches|--count ]]; then
  LIMIT=50
  [ "$BUDGET" = "strict" ] && LIMIT=30
  NEW="$CMD | head -$LIMIT"
  MSG="token-optimizer: capped recursive grep at $LIMIT matching lines. Prefer the Grep tool with head_limit for searches."
fi

[ -z "$NEW" ] && exit 0
[ "$NEW" = "$CMD" ] && exit 0

# ---- emit updatedInput (merge over the original tool_input) ------------------
if [ "$TO_HAS_JQ" = 1 ]; then
  OUT="$(printf '%s' "$INPUT" | jq -c --arg c "$NEW" --arg m "$MSG" '
    {hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input + {command: $c})}}
    + (if $m == "" then {} else {systemMessage: $m} end)' 2>/dev/null)" || exit 0
else
  OUT="$(printf '%s' "$INPUT" | "$TO_PY_BIN" -c '
import sys, json
try:
    d = json.load(sys.stdin)
    ti = dict(d.get("tool_input") or {})
    ti["command"] = sys.argv[1]
    out = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": ti}}
    if sys.argv[2]:
        out["systemMessage"] = sys.argv[2]
    print(json.dumps(out))
except Exception:
    pass' "$NEW" "$MSG" 2>/dev/null)" || exit 0
fi
[ -z "$OUT" ] && exit 0

state_update rewrites+=1 >/dev/null 2>&1
printf '%s\n' "$OUT"
exit 0
