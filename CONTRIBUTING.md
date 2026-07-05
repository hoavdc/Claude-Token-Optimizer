# Contributing

Thanks for helping make Claude Code sessions cheaper for everyone.

## Local development & testing

1. Clone the repo and make your changes.
2. Run the offline test suite (needs bash + jq, no Claude Code required):

   ```bash
   bash plugins/token-optimizer/scripts/tests/run-tests.sh
   ```

3. Test inside Claude Code from the repo root:

   ```
   /plugin marketplace add .
   /plugin install token-optimizer@claude-token-optimizer
   ```

   Then restart the session and check `/hooks` lists the four hook events, and both `/token-optimizer:token-status` and `/token-optimizer:budget` appear in the command list. Use `claude --debug` to watch hook executions.

4. Validate before pushing:

   ```bash
   claude plugin validate .
   claude plugin validate ./plugins/token-optimizer
   ```

## Commit convention

This repo uses [Conventional Commits](https://www.conventionalcommits.org/); releases are automated from them:

- `feat: ...` → minor version bump
- `fix: ...` → patch version bump
- `feat!: ...` or a `BREAKING CHANGE:` footer → major version bump
- `docs:`, `chore:`, `test:`, `ci:` → no release

## Adding a rewrite rule

Command rewrites live in `plugins/token-optimizer/scripts/rewrite-verbose-cmd.sh` in the "rewrite table" `if/elif` chain. To add one:

1. Add an `elif` branch. Rules of the house:
   - Match conservatively (anchored patterns). When in doubt, don't rewrite.
   - Never touch commands with pipes, redirects, heredocs, or substitutions — the safety gates above the table already exclude them; don't weaken the gates.
   - Never alter write/delete semantics.
   - Set `NEW` (the rewritten command) and optionally `MSG` (a short systemMessage explaining the rewrite).
2. Add a fixture in `scripts/tests/fixtures/` (input JSON with your command) and 2 assertions in `scripts/tests/run-tests.sh`: the rewrite happens, and a near-miss variant passes through untouched.
3. Run the test suite and shellcheck:

   ```bash
   bash plugins/token-optimizer/scripts/tests/run-tests.sh
   shellcheck --severity=error plugins/token-optimizer/scripts/*.sh
   ```

## Release process

Releases are automated with [Release Please](https://github.com/googleapis/release-please) (chosen over a manual sync script because its JSON updater keeps `plugin.json` and `marketplace.json` versions in sync declaratively):

1. Merge PRs with conventional-commit titles into `main`.
2. Release Please maintains a release PR that bumps `version.txt`, `plugins/token-optimizer/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `CHANGELOG.md`.
3. Merging that PR tags a GitHub Release automatically.

Manual fallback (if the workflow is ever disabled): bump the version in the three files above, update `CHANGELOG.md`, commit as `chore(release): x.y.z`, tag `vx.y.z`, and push the tag.
