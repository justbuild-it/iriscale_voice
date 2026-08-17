# iriscale voice

**Let your coding agents tell you when they are done and need attention.**

Run several Claude Code sessions, walk away, and hear *"billing service done"* or
*"iriscale voice wants to run git push"* from across the room — instead of tabbing
through terminals to see who's stuck.

- Speaks the **session name** (`/rename` it, or it uses the folder name)
- **Done · stopped with an error · wants to run `<command>` · waiting for you**
- Presets from *"just tell me when it's done"* to *"tell me everything"*
- Concurrent sessions **queue** instead of talking over each other
- macOS, Windows, Linux — uses the voice your OS already has. **Zero dependencies.**

## Install (30 seconds)

Inside Claude Code:

```
/plugin marketplace add justbuild-it/iriscale_voice
/plugin install iriscale-voice@iriscale
```

Then run `/iriscale-voice:test` — you should hear it. (Type `/iriscale-voice:` and autocomplete lists every command.) That's it; the `standard` preset is on.

> Windows: hooks run through Git Bash, which nearly every Claude Code install on
> Windows already has. If `sh` isn't on your PATH, install
> [Git for Windows](https://git-scm.com/download/win).

## Choose how chatty

```
/iriscale-voice:preset basic     # done + waiting for you. Nothing else.
/iriscale-voice:preset standard  # + errors + "wants to run …". Quiet on turns under 30 s.  (default)
/iriscale-voice:preset verbose   # + subagents, session end
/iriscale-voice:mute             # silence, stays installed      /iriscale-voice:unmute
/iriscale-voice:quiet 22-8       # nothing between 10 pm and 8 am
/iriscale-voice:status           # what's configured
/iriscale-voice:config list      # every setting: current value, default, meaning
/iriscale-voice:help             # everything else
```

Or edit `~/.claude/iriscale-voice.conf` by hand — it's just `key=value` lines. Every
knob is in [docs/CONFIG.md](docs/CONFIG.md).

The same thing exists as a normal command, **`iriscale-voice`**, for use outside Claude
Code (`iriscale-voice --help`, `iriscale-voice config list`, …). One symlink puts it on
your PATH — see [docs/CONFIG.md → Command line](docs/CONFIG.md#command-line).

## What it says

| when | you hear |
|---|---|
| turn finishes | *"my service done"* — *"…done after 6 minutes"* for long ones |
| turn dies (rate limit, billing, auth) | *"my service stopped: rate limit"* |
| needs permission | *"my service wants to run git push origin main"* / *"…wants to use Edit"* |
| Claude has been waiting on you | *"my service is waiting for you"* |
| subagent / session end *(verbose)* | *"…subagent done"*, *"…session ended"* |

Underscores and hyphens are spoken as spaces, so name sessions like `payments-api`.

## How it works

Claude Code [hooks](https://code.claude.com/docs/en/hooks) call one POSIX shell
script, [`bin/iriscale-voice`](bin/iriscale-voice), with the event's JSON on stdin. The script
resolves the session name, applies your preset and gates (quiet hours, mute lists,
minimum turn length), then speaks through the OS: `System.Speech` on Windows, `say`
on macOS, `spd-say`/`espeak` on Linux (falling back to a desktop notification, then a
bell). No `jq`, `node`, or `python` needed.

## Other agents

Claude Code today. Codex CLI, Copilot CLI, Grok Build and Gemini CLI use the same
hook shape and are next; Cursor, Junie, Devin, OpenCode and more are mapped out in
[docs/PLATFORMS.md](docs/PLATFORMS.md). If you use one of them and want it sooner,
open an issue with a sample hook payload — that's the only thing we can't produce here.

## Roadmap

Spoken one-line summaries of *what* was done, escalation when a permission prompt sits
unanswered, earcons, a multi-session status board, and the other-agent adapters above —
tracked in [docs/ROADMAP.md](docs/ROADMAP.md). Issues and PRs welcome.

## Develop

```sh
sh test/run.sh                                  # 89 checks, every event × every preset, silent
IRISCALE_VOICE_DEBUG=1 sh bin/iriscale-voice Stop < payload.json
claude plugin validate .                        # manifests
claude plugin marketplace add /path/to/checkout && claude plugin install iriscale-voice@iriscale
```

`claude plugin update` only re-copies on a version bump — while iterating locally,
`claude plugin uninstall iriscale-voice@iriscale && claude plugin install iriscale-voice@iriscale`.

## Upgrading

```
/plugin marketplace update iriscale
```
then **restart Claude Code**. A version change is not picked up by `/reload-plugins` — the
running session keeps the plugin directory it started with, so new or renamed commands
only appear after a restart (`/exit`, then `claude --continue` keeps your conversation).

MIT © Iriscale
