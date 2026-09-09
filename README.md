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
- One POSIX shell script, **zero dependencies**, speaking through the voice your OS
  already has. Verified daily on Windows by the maintainers; macOS and Linux run the
  same script and pass CI, but their speech backends (`say`, `spd-say`) are tested by
  users, not by us — [reports welcome](https://github.com/justbuild-it/iriscale_voice/issues).
- Tells you what it's waiting on — *"…to run git push origin main --force"* — with
  anything that looks like a credential scrubbed before it reaches the speaker or the
  log. Shared office? `command_detail=program` speaks the program name only. See
  [SECURITY.md](SECURITY.md).

## Install (30 seconds)

### Claude Code (any OS)

Inside Claude Code:

```
/plugin marketplace add justbuild-it/iriscale_voice
/plugin install iriscale-voice@iriscale
```

Then run `/iriscale-voice:test` — you should hear it. Silent on Windows? The same command
says why: Windows keeps a per-app volume for PowerShell in the Volume Mixer, and every
announcement is spoken through PowerShell, so a stray drag to 0% there mutes the plugin
everywhere. `/iriscale-voice:test --fix` puts it back to 100%. (Type `/iriscale-voice:` and autocomplete lists every command.) That's it; the `standard` preset is on.

> Windows: hooks run through Git Bash, which nearly every Claude Code install on
> Windows already has. If `sh` isn't on your PATH, install
> [Git for Windows](https://git-scm.com/download/win).

### Codex CLI (macOS, Linux, Windows)

One command, wherever you have Node 18+:

```sh
npx iriscale-voice@latest install codex --apply
```

> The same installer does Claude Code without the plugin —
> `npx iriscale-voice@latest install claude --apply` — for one install path across every
> agent. It writes the seven hooks into `~/.claude/settings.json`, the skill, and the
> commands as `/iriscale-voice-status` (flat files; only the plugin gets the `:` spelling).
> The plugin above is still the better route for Claude Code — self-updating, edits none of
> your files — and running **both** speaks everything twice, so the installer refuses when
> it finds the plugin enabled. `iriscale-voice doctor claude` checks all of it.
> See [docs/install/npm.md](docs/install/npm.md).

Restart Codex and your terminal, open `/hooks`, and trust the two hooks that show
`Installed 1`. It installs the script to a stable directory, adds `iriscale-voice` to
your `PATH`, installs the `$iriscale-voice` Codex skill, and merges Codex configuration
— backing up every file it touches and rewriting only its own lines. Reversed exactly by
`npx iriscale-voice@latest uninstall codex`. Details: [docs/install/npm.md](docs/install/npm.md).

Codex speaks as soon as you restart it — the hooks hold absolute paths, so nothing here
depends on your `PATH`. To *also* run the CLI yourself, put its directory on `PATH` (the
installer prints the exact line for your shell) or use `npm install -g iriscale-voice`:

```sh
iriscale-voice status
iriscale-voice doctor codex
iriscale-voice test
```

**Node is needed to install, never to run**: Codex calls the same zero-dependency shell
script directly. Want the config but not the installer? `npx iriscale-voice@latest
install codex` (no `--apply`) prints exactly what to paste and writes nothing.

Windows without Node? The PowerShell installer does the same job, and additionally sets
up tab completion (Git for Windows is its only prerequisite):

```powershell
irm https://raw.githubusercontent.com/justbuild-it/iriscale_voice/v0.1.24/install.ps1 | iex
```

Prefer to read either installer first? [SECURITY.md](SECURITY.md) shows how.

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
Code (`iriscale-voice --help`, `iriscale-voice config list`, …). `npm install -g
iriscale-voice` puts it on your `PATH` on any OS (so does either Codex installer);
manual setup is in [docs/CONFIG.md → Command line](docs/CONFIG.md#command-line).

## See them all at once: the session board

```
iriscale-voice board
```

A live list of every session — needs your answer / ready for review / working / idle —
with how long it's been there and what was last said. **Click a row (or press its
number) to bring that session's window to the front** (Windows; Linux with `wmctrl`;
not yet on macOS). When sessions are tabs inside one IDE window it raises that window
and names the tab. It repaints only when something changes, so it's ~5 MB of idle shell.
Give it a small Windows Terminal window off to the side (works for Claude Code and Codex
sessions alike):

```
wt -w iriscale --size 64,18 --pos 1180,80 --title sessions iriscale-voice board
```

Or let it look after itself — with this on, the next session event opens the window
if it isn't already there (after an update, a reboot, a stray close):

```
/iriscale-voice:config set board_autostart true      # /iriscale-voice:board opens it once
```

`iriscale-voice sessions` prints one frame for scripts. Details: [docs/CONFIG.md](docs/CONFIG.md#the-session-board).

## What it says, and when

| the session… | you hear | what to do |
|---|---|---|
| finished its turn | *"my service done"* — *"…done after 6 minutes"* for long ones | review it when you reach a stopping point |
| finished a turn but background agents or tasks are still running | nothing (verbose: *"…finished a step, 1 agent still running"*) - the board shows *working · waiting for 1 agent: …* | nothing; it wakes itself and says "done" when the whole job is finished |
| paused for a `/loop` or scheduled wake-up | nothing (verbose: *"…paused until its next wake-up"*) - the board shows *scheduled* | nothing |
| is blocked on a permission prompt | *"my service is waiting for your answer to run git push origin main"* / *"…to use Edit"* — credential-looking words are spoken as "redacted" | it can't continue until you answer — switch now |
| died (rate limit, billing, auth) | *"my service stopped: rate limit"* | don't wait for it |
| a minute passed and no key was pressed there | *"my service is waiting for you"* | the board marks it **needs your review** |
| still needs you after a while | *"payments still needs your answer, 10 minutes"* — merged when several: *"still waiting: payments needs your answer, billing ready for review"* | answers at 3 and 10 min, review at 15, errors at 10, then silence — see below |
| you come back after 10 quiet minutes | *"while you were away: payments needs your answer, billing ready for review"* | one summary, before your prompt runs |
| subagent / session end *(verbose preset)* | *"…sub agent done"*, *"…session ended"* | usually noise; off by default |

Each first line is spoken **once**. Reminders follow only while a session still needs
you: merged into one sentence when several do, skipped while you are typing elsewhere
(`remind_pause`), and capped by the schedule (`remind_answer` 3,10 · `remind_review` 15 ·
`remind_action` 10 minutes; `basic` never reminds). Then silence; the board keeps the row.

**A session counts as reviewed when you press any key in it within a minute of it
finishing. Clicking into it or giving it focus is not enough** — that is what Claude
Code's own idle notice keys on, and the plugin reads that notice. Codex sessions stay
*ready for review* until your next prompt there. The `standard` preset also
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
[Codex setup](docs/install/codex.md) — or [npm/npx](docs/install/npm.md) on any OS —
including installation, diagnostics, completion, updates, and removal. Copilot CLI, Grok
Build, Gemini CLI, Cursor, and the remaining agents are mapped out in
[docs/PLATFORMS.md](docs/PLATFORMS.md).

## Roadmap

Spoken one-line summaries of *what* was done, escalation when a permission prompt sits
unanswered, earcons, menu-bar/tray versions of the board, and the other-agent adapters
above — tracked in [docs/ROADMAP.md](docs/ROADMAP.md). Issues and PRs welcome.

## Develop

```sh
sh test/run.sh                                  # full event, CLI, installer, and performance suite
sh test/npm.sh                                  # the npm installer, against a throwaway ~/.codex
IRISCALE_VOICE_DEBUG=1 sh bin/iriscale-voice Stop < payload.json   # shows on the board too: forget --all after
claude plugin validate .                        # manifests
claude plugin marketplace add /path/to/checkout && claude plugin install iriscale-voice@iriscale
```

`claude plugin update` only re-copies on a version bump — while iterating locally,
`claude plugin uninstall iriscale-voice@iriscale && claude plugin install iriscale-voice@iriscale`.

## Upgrading

Claude Code plugin:
```
/plugin marketplace update iriscale
```
then **restart Claude Code**. A version change is not picked up by `/reload-plugins` — the
running session keeps the plugin directory it started with, so new or renamed commands
only appear after a restart (`/exit`, then `claude --continue` keeps your conversation).

npm install: `npx iriscale-voice@latest update` (or `iriscale-voice update` from a
global install), then restart the agent — upgrading the package alone leaves the copy
your hooks run on the old version. Windows installer: `iriscale-voice update`.
Checkout: `git pull`.

MIT © Iriscale
