# iriscale voice

**Run many coding-agent sessions in parallel. Each one tells you, by name, the moment
it's ready for review or needs your attention.**

Coding agents are at their best on long-running tasks — a refactor here, a test suite
there, a migration in a third terminal. The bottleneck is you: you can't watch five
terminals, so you either poll them (and lose your focus) or forget one (and it sits
finished, or blocked on a yes/no, for twenty minutes).

iriscale voice removes the polling. You keep working in whichever session has your
attention; the others speak up when — and only when — they need you:

- *"billing service done after 6 minutes"* → ready for review
- *"payments api is waiting for your answer to run git push"* → blocked on you, right now
- *"data migration stopped: rate limit"* → died, don't wait for it

You hear **which** session and **why**, without looking, so you can finish the thought
you're on and then switch. That's the whole product.

- Speaks the **session name** (`/rename` it, or it uses the folder name)
- **Done · stopped with an error · waiting for your answer to run `<command>`**
- Presets from *"just tell me when it's done"* to *"tell me everything"*
- Concurrent sessions **queue** instead of talking over each other; the same line is never
  repeated inside a minute
- Works for **Claude Code** and **Codex CLI** today, one config for both; more agents mapped
- macOS, Windows, Linux — uses the voice your OS already has. **Zero dependencies.**

## Install (30 seconds)

### Codex on Windows

Run once in PowerShell (Git for Windows is the only prerequisite):

```powershell
irm https://raw.githubusercontent.com/justbuild-it/iriscale_voice/main/install.ps1 | iex
```

Restart Codex and your terminal, open `/hooks`, and trust the two hooks that show
`Installed 1`. The installer adds `iriscale-voice` to your user `PATH`, enables
PowerShell tab completion, safely merges Codex configuration, and creates backups.
Type `$iriscale-voice` in Codex for the discoverable skill, or use the CLI anywhere:

```powershell
iriscale-voice status
iriscale-voice doctor codex
iriscale-voice <Tab>
```

### Claude Code

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
/iriscale-voice:preset standard  # + errors + "waiting for your answer …". Quiet on turns under 30 s.  (default)
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
Code (`iriscale-voice --help`, `iriscale-voice config list`, …). The Windows Codex
installer adds it to `PATH`; manual macOS/Linux setup is in
[docs/CONFIG.md → Command line](docs/CONFIG.md#command-line).

## See them all at once: the session board

```
iriscale-voice board
```

A live list of every session — needs your answer / ready for review / working / idle —
with how long it's been there and what was last said. **Click a row (or press its
number) to bring that session's window to the front.** It repaints only when something
changes, so it's ~5 MB of idle shell. Give it a small Windows Terminal window off to the
side (works for Claude Code and Codex sessions alike):

```
wt -w iriscale --size 64,18 --pos 1180,80 --title sessions iriscale-voice board
```

`iriscale-voice sessions` prints one frame for scripts. Details: [docs/CONFIG.md](docs/CONFIG.md#the-session-board).

## What it says, and when

| the session… | you hear | what to do |
|---|---|---|
| finished its turn | *"my service done"* — *"…done after 6 minutes"* for long ones | review it when you reach a stopping point |
| is blocked on a permission prompt | *"my service is waiting for your answer to run git push origin main"* / *"…to use Edit"* | it can't continue until you answer — switch now |
| died (rate limit, billing, auth) | *"my service stopped: rate limit"* | don't wait for it |
| has sat idle waiting for input | *"my service is waiting for you"* | the agent's own reminder, relayed once |
| subagent / session end *(verbose preset)* | *"…sub agent done"*, *"…session ended"* | usually noise; off by default |

Each of these is spoken **once**. Nothing repeats on its own, and the `standard` preset
stays silent on turns under 30 seconds so it isn't chatty while you're actively working
in that session. Underscores and hyphens are spoken as spaces, so name sessions like
`payments-api`.

## A typical hour

1. Start three sessions: `/rename billing-service`, `/rename payments-api`, `/rename docs`.
   Give each a task that'll take a while.
2. Work in `docs`. Four minutes later: *"billing service done after 4 minutes."* Finish your
   paragraph, then go review it.
3. While reviewing: *"payments api is waiting for your answer to run pytest."* Tab over,
   press yes, tab back. Ten seconds.
4. Nothing else speaks until something actually changes.

## How it works

Claude Code [hooks](https://code.claude.com/docs/en/hooks) call one POSIX shell
script, [`bin/iriscale-voice`](bin/iriscale-voice), with the event's JSON on stdin. The script
resolves the session name, applies your preset and gates (quiet hours, mute lists,
minimum turn length), then speaks through the OS: `System.Speech` on Windows, `say`
on macOS, `spd-say`/`espeak` on Linux (falling back to a desktop notification, then a
bell). No `jq`, `node`, or `python` needed.

## Other agents

**Codex CLI is supported and verified live.** See the one-command
[Codex setup](docs/install/codex.md), including installation, diagnostics, completion,
updates, and removal. Copilot CLI, Grok
Build, Gemini CLI, Cursor, and the remaining agents are mapped out in
[docs/PLATFORMS.md](docs/PLATFORMS.md).

## Roadmap

Spoken one-line summaries of *what* was done, escalation when a permission prompt sits
unanswered, earcons, a multi-session status board, and the other-agent adapters above —
tracked in [docs/ROADMAP.md](docs/ROADMAP.md). Issues and PRs welcome.

## Develop

```sh
sh test/run.sh                                  # full event, CLI, installer, and performance suite
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
