# token-optimizer

A Claude Code plugin that reduces token consumption in coding sessions — typically an estimated 40–70% depending on workload — without degrading output quality. All savings figures are rough estimates and vary by project and working style.

## How it saves tokens

| Mechanism | Component | What it saves |
|---|---|---|
| Rewrite verbose commands (`git status` → `--short`, unbounded `git diff` → `--stat`, `find` without depth limit, `cat` on huge files, noisy `npm`/`pip` installs, unbounded `grep -r`) | `PreToolUse` hook → `scripts/rewrite-verbose-cmd.sh` | Output never gets generated, so it never enters context |
| Compress oversized Bash output (stack traces → head+tail around the error, build logs → strip progress noise, everything else → head + tail with an elided-lines marker) | `PostToolUse` hook → `scripts/filter-bash-output.sh` | Cuts long outputs down to the configured line budget |
| Compaction reminders every N turns, with keep/drop suggestions | `Stop` hook → `scripts/context-meter.sh` | Encourages compacting before context balloons |
| Token-discipline rules injected once at session start (<120 words) | `SessionStart` hook → `scripts/session-init.sh` + `skills/token-discipline` | Steers the model toward Grep-then-Read-with-limits, no file echoing, no re-reads |
| Cheap-model delegation | agents `quick-reader`, `quick-reviewer`, `doc-writer` (Haiku) | Simple reads, reviews, and docs run on the cheapest model instead of the main one |
| Prompt-cache preservation | design constraint across all hooks | Dynamic content is only injected at session start or next to tool results — never near the top of the prompt — so the stable prefix stays cached |

## Configuration

Three settings, prompted for when you enable the plugin (stored under `pluginConfigs` in `settings.json`):

| Setting | Default | Effect |
|---|---|---|
| `maxToolOutputLines` | 150 | Bash output longer than this gets compressed |
| `compactReminderTurns` | 12 | Remind about `/compact` every N turns |
| `aggressiveMode` | false | Start sessions in `strict` budget mode |

At runtime, switch modes per project with `/token-optimizer:budget strict|normal|off`. Check activity with `/token-optimizer:token-status`.

State lives in `<project>/.claude/token-optimizer-state.json` (turn counter, rewrite/truncation counters, budget mode). Safe to delete at any time; add it to `.gitignore`.

## Safety model

Safety over savings, always:

- Every script exits `0` on any error, so a hook failure can never block a tool call.
- Commands containing pipes, redirects, heredocs, command substitution, or multiple statements are never rewritten.
- Write/delete commands (`rm`, `mv`, `git push`, `git commit`, …) are never touched.
- No hook emits `permissionDecision`, so nothing is ever auto-approved or auto-denied.
- `updatedToolOutput` only changes what Claude sees — the command has already run unmodified.

## Testing

Offline tests (no Claude Code needed):

```bash
bash plugins/token-optimizer/scripts/tests/run-tests.sh
```

Test-run the plugin in a session:

```bash
claude --plugin-dir ./plugins/token-optimizer
```

Then verify:

- `/hooks` — should list SessionStart, PreToolUse (Bash), PostToolUse (Bash), and Stop entries from `token-optimizer`.
- `claude --debug` — hook executions and their JSON output appear in the debug log.
- Ask Claude to run `git status` — the executed command should be `git status --short --branch`.
- `/token-optimizer:token-status` — reports counters after some activity.

## Known limitations

- **Bash-only interception.** Hooks match the `Bash` tool. Built-in `Read`/`Grep`/`Glob` calls are not filtered by hooks; those are covered by the session-start rules and the `token-discipline` skill (guidance, not enforcement).
- **Savings are estimates.** The `token-status` figure is `elided lines × ~10 tokens/line` — a rough heuristic.
- **Hook config reloads on session start.** After installing or upgrading the plugin, restart the session for hook changes to load. (Budget-mode changes via `/token-optimizer:budget` apply immediately — the scripts read state on every call.)
- **`jq` or `python3` required.** Scripts prefer `jq` and fall back to `python3`. If neither is on `PATH`, hooks pass everything through untouched (nothing breaks; you just save nothing).
- **Turn counting is per project directory**, not per Claude session-id; parallel sessions in one project share a counter.

## Disabling parts individually

- Everything, temporarily: `/token-optimizer:budget off` (command rewriting + output filtering).
- Compaction reminders: set `compactReminderTurns` high (e.g. 999) in the plugin config.
- A single hook: remove its entry from `hooks/hooks.json` in a local fork, or disable the whole plugin with `/plugin` → disable.
- Agents/skill: they're passive — they only act when the main model delegates or the skill triggers.

## License

MIT
