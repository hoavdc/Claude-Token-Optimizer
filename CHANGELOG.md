# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-05

### Added

- `PreToolUse` hook that rewrites token-hungry Bash commands into leaner equivalents
  (`git status` → `--short --branch`, unbounded `git log`/`git diff`, `find` without
  `-maxdepth`, `cat` on large files, noisy `npm`/`pip` installs, unbounded `grep -r`),
  with hard safety gates: pipelines, redirects, heredocs, and write/delete commands
  are never touched.
- `PostToolUse` hook that compresses oversized Bash output before it enters context:
  stack traces keep head + tail around the error, build/test logs drop progress noise,
  everything else gets head + tail with an elided-lines marker.
- `Stop` hook that counts turns and reminds about `/compact` every N turns with
  keep/drop suggestions.
- `SessionStart` hook injecting a <120-word token-discipline context block.
- Three Haiku subagents: `quick-reader` (file/directory summaries), `quick-reviewer`
  (small diffs, simple unit tests, lint), `doc-writer` (docstrings, comments, READMEs).
- `token-discipline` skill with six token-efficiency rules.
- Slash commands: `/token-optimizer:token-status` (session stats + rough savings
  estimate) and `/token-optimizer:budget strict|normal|off` (runtime aggressiveness).
- User config: `maxToolOutputLines` (150), `compactReminderTurns` (12),
  `aggressiveMode` (false).
- Offline test suite for all hook scripts (35 assertions, no Claude Code required).

[0.1.0]: https://github.com/hoavdc/Claude-Token-Optimizer/releases/tag/v0.1.0
