# token-optimizer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/hoavdc/Claude-Token-Optimizer/actions/workflows/validate.yml/badge.svg)](https://github.com/hoavdc/Claude-Token-Optimizer/actions/workflows/validate.yml)
[![Release](https://img.shields.io/github/v/release/hoavdc/Claude-Token-Optimizer)](https://github.com/hoavdc/Claude-Token-Optimizer/releases)

A Claude Code plugin that automatically reduces token consumption in coding sessions — rewriting verbose commands before they run, compressing oversized tool output before it enters context, reminding you to compact at the right time, and routing simple tasks to cheap Haiku subagents. Estimated savings of 40–70% depending on workload; **these figures are estimates and vary considerably by project and working style**.

## Installation

```
/plugin marketplace add hoavdc/Claude-Token-Optimizer
/plugin install token-optimizer@claude-token-optimizer
```

Restart the session after install so the hooks load.

For teams, install at project scope so everyone gets it:

```
claude plugin install token-optimizer@claude-token-optimizer --scope project
```

Or add the marketplace to your repo's `.claude/settings.json` so teammates are prompted automatically when they trust the folder:

```json
{
  "extraKnownMarketplaces": {
    "claude-token-optimizer": {
      "source": {
        "source": "github",
        "repo": "hoavdc/Claude-Token-Optimizer"
      }
    }
  }
}
```

## What it does

| Mechanism | Component | What it saves |
|---|---|---|
| Rewrites token-hungry commands (`git status` → `--short --branch`, unbounded `git log`/`git diff`, `find` without `-maxdepth`, `cat` on huge files, noisy `npm`/`pip` installs, unbounded `grep -r`) | hook (`PreToolUse`) | Verbose output is never generated, so it never enters context |
| Compresses oversized Bash output (stack traces keep the error, build logs drop progress noise, everything else keeps head + tail with an elided-lines marker) | hook (`PostToolUse`) | Long outputs shrink to the configured line budget |
| Reminds about `/compact` every N turns, with keep/drop suggestions | hook (`Stop`) | Compaction happens before context balloons |
| Injects <120 words of token-discipline rules at session start | hook (`SessionStart`) + skill (`token-discipline`) | Fewer whole-file reads, no file echoing, no redundant re-reads |
| Delegates simple work to cheap models | agents (`quick-reader`, `quick-reviewer`, `doc-writer`, all Haiku) | File summaries, small reviews, and docs cost Haiku prices, not Opus/Sonnet |
| Preserves prompt caching | design constraint | Dynamic content is injected only at session start or next to tool results — the stable prompt prefix is never touched mid-session |
| Runtime stats & control | commands (`/token-optimizer:token-status`, `/token-optimizer:budget`) | Visibility into what the plugin saved; per-project aggressiveness control |

## Configuration

Claude Code prompts for these when you enable the plugin:

| Setting | Default | Effect |
|---|---|---|
| `maxToolOutputLines` | 150 | Bash output longer than this gets compressed |
| `compactReminderTurns` | 12 | Remind about `/compact` every N turns |
| `aggressiveMode` | false | Start sessions in strict budget mode |

At runtime: `/token-optimizer:budget strict|normal|off` switches filtering aggressiveness per project, effective immediately (`off` disables rewriting and filtering entirely).

## Verifying it works

1. `/hooks` — you should see `token-optimizer` entries under SessionStart, PreToolUse (Bash), PostToolUse (Bash), and Stop.
2. `claude --debug` — hook executions and their JSON output appear in the debug log.
3. Ask Claude to run `git status` — the executed command becomes `git status --short --branch`.
4. `/token-optimizer:token-status` — reports turns, rewrites, truncations, and a rough savings estimate.

## Known limitations

- **Only the Bash tool is intercepted.** Built-in Read/Grep/Glob calls are guided by the skill and session rules, not enforced by hooks.
- **Savings figures are rough estimates** (`elided lines × ~10 tokens/line`).
- **Hooks load at session start** — after installing or updating the plugin, restart the session. Budget changes via the command apply immediately.
- **Requires `jq` or `python3`** on PATH. With neither, hooks pass everything through untouched (nothing breaks, nothing is saved).

## Disabling parts individually

- All filtering, temporarily: `/token-optimizer:budget off`
- Compaction reminders: set `compactReminderTurns` to a large value
- Whole plugin: `/plugin` → token-optimizer → disable
- See [the plugin README](plugins/token-optimizer/README.md) for details

## Uninstall

```
/plugin uninstall token-optimizer@claude-token-optimizer
/plugin marketplace remove claude-token-optimizer
```

Optionally delete the per-project state file: `.claude/token-optimizer-state.json`.

## Contributing & License

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MIT](LICENSE).
