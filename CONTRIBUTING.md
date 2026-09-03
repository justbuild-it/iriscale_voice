# Contributing

Small project, simple rules. The point of every rule here is that anyone can see
**what** changed, **why**, and **which version** has it.

## Every change is a pull request

No direct pushes to `main` — including maintainers, including one-line fixes.

1. Branch: `fix/<what>`, `feat/<what>`, `docs/<what>`.
2. Commit in [Conventional Commits](https://www.conventionalcommits.org/) form
   (`fix: …`, `feat: …`, `docs: …`). The body says *why*, not just what.
3. Run `sh test/run.sh` — it must pass, and a fix should add a check that would have
   caught the bug.
4. Add a line under `[Unreleased]` in `CHANGELOG.md`.
5. Open the PR. Description = the changelog line expanded: symptom, root cause, fix,
   how it was verified. If a user reported it, link the issue.

## Releasing

A release is its own small PR:

1. Bump the version in **all four** places — `VERSION=` in `bin/iriscale-voice`,
   `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and
   `.codex-plugin/plugin.json` (`test/run.sh`
   fails if they disagree). `claude plugin update` only re-copies on a version
   change, so a fix without a bump never reaches installed users.
   - **Versioning policy:** while we're pre-1.0, every release — fixes and features
     alike — bumps the **patch** number: 0.1.1 → 0.1.2 → 0.1.3. Small, frequent,
     visible releases beat batching. The minor number bumps only for a config- or
     behavior-breaking change (e.g. renamed keys); 1.0.0 when the config format is
     frozen.
2. Move `[Unreleased]` in `CHANGELOG.md` under the new version with today's date.
   Update the pinned tag in the README's install one-liner, `SECURITY.md`, and the
   `-Ref` default at the top of `install.ps1` to the new version (a test checks they agree).
3. Merge, then **pull and verify before tagging** — never tag in the same command chain
   as the pull (a transient fetch failure once produced a v0.1.12 tag on 0.1.11 content,
   and the tag ruleset rightly refuses to move tags):
   ```sh
   git checkout main && git pull --ff-only
   [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "not at origin/main"; exit 1; }
   grep -q '^VERSION="X.Y.Z"' bin/iriscale-voice || { echo "version mismatch"; exit 1; }
   ```
   then tag and publish notes from the changelog:
   ```sh
   git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
   gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <(sed -n '/^## \[X.Y.Z\]/,/^## \[/p' CHANGELOG.md | sed '$d')
   ```
Users get it with `/plugin marketplace update iriscale`.

## Local iteration

```sh
sh test/run.sh                          # silent, uses a throwaway config dir
IRISCALE_VOICE_DEBUG=1 sh bin/iriscale-voice Stop < payload.json
claude plugin validate .
claude plugin uninstall iriscale-voice@iriscale && claude plugin install iriscale-voice@iriscale
```

Never run `iriscale-voice set …` against your real `~/.claude/iriscale-voice.conf` from a
test — set `CLAUDE_CONFIG_DIR` to a scratch dir (the harness already does).

## Adding another agent

See `docs/PLATFORMS.md`. An adapter PR needs: the field/event aliases in
`bin/iriscale-voice`, a synthetic payload test, and `docs/install/<agent>.md` with the exact
config to paste. If you can, include a real payload captured from the agent — that's
the one thing maintainers can't produce for agents they don't run.

## Naming things users type

Slash commands, the CLI, config keys: name them after the product or the thing itself,
never after the mechanism. And check for collisions first — Claude Code's built-in
`/voice` (dictation mode) silently shadowed ours for a whole release. Plugin commands
are always documented in their namespaced form (`/iriscale-voice:status`); `test/run.sh`
fails if any doc mentions a bare `/<command>`, because built-ins shadow bare names.

## Guard tests worth knowing about

`test/run.sh` is the gate, and several checks exist to stop specific past bugs from
returning: the version must agree across all four manifests; every `config list` key
must be documented in `docs/CONFIG.md`; the hook path may spawn at most one text tool;
a stubbed 3 s speaker must not block the hook for more than 2 s; `sessions --color` must
emit real escape bytes and `--plain` none; a permission prompt must never speak a token;
a traversal `session_id` must stay inside the state dir; `clean()` must never pass a
quote, backslash, backtick or `$`. Add one whenever you fix a bug.

## Keep the hook path cheap

`bin/iriscale-voice` runs on every hook event. On Windows/MSYS each external process
(`sed`, `grep`, `tr`, ...) costs 25-50 ms to spawn, and 0.1.4 spent ~1.8 s per event that
way. Rules: read the config once (`load_conf`); use `cfgv VAR key default` (assigns, no
subshell) instead of `$(cfg ...)` on the hook path; extract JSON fields with `jget` (pure
shell); prefer parameter expansion over `sed`/`tr`. `test/run.sh` fails if the hook path
spawns more than one text tool. If you must add a process, add it to a CLI path, not the
event path.
