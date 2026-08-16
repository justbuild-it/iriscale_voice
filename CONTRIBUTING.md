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

1. Bump `version` in **both** `.claude-plugin/plugin.json` and
   `.claude-plugin/marketplace.json` — `claude plugin update` only re-copies on a
   version change, so a fix without a bump never reaches installed users.
   - patch: fixes · minor: new events/settings/agents · major: breaking config changes
2. Move `[Unreleased]` in `CHANGELOG.md` under the new version with today's date.
3. Merge, then tag and publish notes from the changelog:
   ```sh
   git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
   gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <(sed -n '/^## \[X.Y.Z\]/,/^## \[/p' CHANGELOG.md | sed '$d')
   ```
Users get it with `/plugin marketplace update iriscale`.

## Local iteration

```sh
sh test/run.sh                          # silent, uses a throwaway config dir
IRISCALE_VOICE_DEBUG=1 sh bin/notify.sh Stop < payload.json
claude plugin validate .
claude plugin uninstall iriscale-voice@iriscale && claude plugin install iriscale-voice@iriscale
```

Never run `notify.sh set …` against your real `~/.claude/iriscale-voice.conf` from a
test — set `CLAUDE_CONFIG_DIR` to a scratch dir (the harness already does).

## Adding another agent

See `docs/PLATFORMS.md`. An adapter PR needs: the field/event aliases in
`bin/notify.sh`, a synthetic payload test, and `docs/install/<agent>.md` with the exact
config to paste. If you can, include a real payload captured from the agent — that's
the one thing maintainers can't produce for agents they don't run.
