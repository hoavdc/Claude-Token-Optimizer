#!/usr/bin/env bash
# token-optimizer shared helpers.
# Supreme rule: safety over savings. Any error -> caller should exit 0 with no
# output so the workflow is never blocked and no command is ever corrupted.
# Requires jq; falls back to python3; if neither exists, helpers return failure
# and callers pass everything through untouched.

TO_HAS_JQ=0
TO_HAS_PY=0
command -v jq >/dev/null 2>&1 && TO_HAS_JQ=1
# Windows/Git Bash often has "python" but not "python3"
TO_PY_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"
[ -n "$TO_PY_BIN" ] && TO_HAS_PY=1

# json_get <dotted.path>  - extract a string/number field from $INPUT
json_get() {
  if [ "$TO_HAS_JQ" = 1 ]; then
    printf '%s' "$INPUT" | jq -r "(.$1 // empty) | if type==\"string\" then . else tostring end" 2>/dev/null
  elif [ "$TO_HAS_PY" = 1 ]; then
    printf '%s' "$INPUT" | "$TO_PY_BIN" -c '
import sys, json
try:
    d = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        d = d.get(k) if isinstance(d, dict) else None
    if d is None:
        sys.exit(0)
    print(d if isinstance(d, str) else json.dumps(d))
except Exception:
    pass' "$1" 2>/dev/null
  else
    return 1
  fi
}

# state_file - echo path to the per-project state file (creates parent dir)
state_file() {
  local root="${CLAUDE_PROJECT_DIR:-}"
  [ -z "$root" ] && root="$(json_get cwd)"
  [ -z "$root" ] && root="."
  mkdir -p "$root/.claude" 2>/dev/null || return 1
  printf '%s' "$root/.claude/token-optimizer-state.json"
}

# state_read - echo state JSON ({} if missing/corrupt)
state_read() {
  local f
  f="$(state_file)" || { printf '{}'; return; }
  if [ -s "$f" ]; then cat "$f" 2>/dev/null || printf '{}'; else printf '{}'; fi
}

# state_update <key=value | key+=n> ... - best-effort, never fails hard.
# Usage: state_update turns=5 rewrites+=1 budget=strict
state_update() {
  local f tmp
  f="$(state_file)" || return 0
  tmp="${f}.tmp.$$"
  if [ "$TO_HAS_JQ" = 1 ]; then
    local prog="."
    local kv key val
    for kv in "$@"; do
      if [[ "$kv" == *"+="* ]]; then
        key="${kv%%+=*}"; val="${kv#*+=}"
        prog="$prog | .${key} = ((.${key} // 0) + ${val})"
      else
        key="${kv%%=*}"; val="${kv#*=}"
        if [[ "$val" =~ ^-?[0-9]+$ ]]; then
          prog="$prog | .${key} = ${val}"
        else
          prog="$prog | .${key} = \"${val}\""
        fi
      fi
    done
    state_read | jq -c "$prog" > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null
  elif [ "$TO_HAS_PY" = 1 ]; then
    STATE_JSON="$(state_read)" "$TO_PY_BIN" -c '
import sys, json, os
try:
    d = json.loads(os.environ.get("STATE_JSON") or "{}")
except Exception:
    d = {}
for kv in sys.argv[2:]:
    try:
        if "+=" in kv:
            k, v = kv.split("+=", 1)
            d[k] = int(d.get(k, 0) or 0) + int(v)
        else:
            k, v = kv.split("=", 1)
            d[k] = int(v) if v.lstrip("-").isdigit() else v
    except Exception:
        pass
try:
    with open(sys.argv[1], "w") as f:
        json.dump(d, f)
except Exception:
    pass' "$f" "$@" 2>/dev/null
  fi
  rm -f "$tmp" 2>/dev/null
  return 0
}

# state_get <key> <default> - read one scalar from the state file
state_get() {
  local v=""
  if [ "$TO_HAS_JQ" = 1 ]; then
    v="$(state_read | jq -r ".$1 // empty" 2>/dev/null)"
  elif [ "$TO_HAS_PY" = 1 ]; then
    v="$(state_read | "$TO_PY_BIN" -c '
import sys, json
try:
    v = json.load(sys.stdin).get(sys.argv[1])
    if v is not None:
        print(v)
except Exception:
    pass' "$1" 2>/dev/null)"
  fi
  [ -z "$v" ] && v="$2"
  printf '%s' "$v"
}

# budget - echo current budget mode: strict | normal | off
# (fast path: plain bash string matching on the state file, no subprocess)
budget() {
  local dflt="normal" f content=""
  [ "${CLAUDE_PLUGIN_OPTION_aggressiveMode:-false}" = "true" ] && dflt="strict"
  f="${CLAUDE_PROJECT_DIR:-.}/.claude/token-optimizer-state.json"
  [ -r "$f" ] && content="$(<"$f")" 2>/dev/null
  case "$content" in
    *'"budget":"off"'* | *'"budget": "off"'*)       printf 'off' ;;
    *'"budget":"strict"'* | *'"budget": "strict"'*) printf 'strict' ;;
    *'"budget":"normal"'* | *'"budget": "normal"'*) printf 'normal' ;;
    *)                                              printf '%s' "$dflt" ;;
  esac
}

# num_opt <env-suffix> <default> - read a numeric plugin option safely
num_opt() {
  local v
  eval "v=\"\${CLAUDE_PLUGIN_OPTION_$1:-}\""
  [[ "$v" =~ ^[0-9]+$ ]] || v="$2"
  printf '%s' "$v"
}
