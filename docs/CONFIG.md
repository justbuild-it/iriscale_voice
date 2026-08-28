# Configuration

Most people never need this page. Pick a preset with `/iriscale-voice:preset basic` and you're
done. Everything below is for tuning.

## Where settings live

`~/.claude/iriscale-voice.conf` — plain `key=value`, one per line, `#` for comments.
Created on first `/iriscale-voice:…` command; safe to edit by hand; re-read on every event, so
there is nothing to restart. It lives outside the plugin folder so updates never
touch it.

Precedence, highest first:

1. `IRISCALE_VOICE_OFF=1` in the environment — instant mute, no file edits
2. `~/.claude/iriscale-voice.conf`
3. The plugin's own setting UI (`preset`), if you set it there
4. Built-in defaults (= the `standard` preset)

## Presets

| preset | speaks on |
|---|---|
| `basic` | turn finished · waiting for you |
| `standard` *(default)* | basic + stopped with an error · wants to run `<command>` / use `<tool>` — and stays silent on turns under 30 s |
| `verbose` | standard + subagent finished · agent finished · session ended |
| `off` | nothing (stays installed) |

## All keys

| key | default | meaning |
|---|---|---|
| `preset` | `standard` | see above |
| `enabled` | `true` | `false` = silent. `/iriscale-voice:mute` sets this |
| `event.<Event>` | *(from preset)* | `on`/`off` — override one event regardless of preset. Events: `Stop`, `StopFailure`, `PermissionRequest`, `idle_prompt`, `agent_completed`, `SubagentStop`, `SessionEnd` |
| `quiet_hours` | *(none)* | `22-8` style, 24-hour, may wrap midnight. Nothing speaks inside the window |
| `min_turn_seconds` | `30` (standard) / `0` | don't announce "done" for turns shorter than this. Errors and permission prompts ignore it — those always speak |
| `say_elapsed` | `true` | append "after N minutes" to "done" when a turn ran 60 s or more |
| `mute_sessions` | *(none)* | comma-separated session names to never announce |
| `only_sessions` | *(none = all)* | comma-separated; if set, announce ONLY these |
| `voice` | OS default | Windows: `Microsoft Zira Desktop`; macOS: any from `say -v ?`; Linux: ignored |
| `rate` | `0` | speaking speed, -10 (slow) to 10 (fast) |
| `volume` | `100` | 0–100 (Windows only; others use system volume) |
| `serialize` | `true` | queue announcements so concurrent sessions never talk over each other |
| `repeat_cooldown` | `60` | seconds; the *same* announcement for the *same* session inside this window is said once. Guards against a looping subagent or a double-firing hook. `0` disables |
| `log` | `~/.claude/iriscale-voice.log` | tab-separated `time  event  text`. `none` to disable |
| `board_ready_minutes` | `15` | on the board, a finished session shows **READY** for this long, then **idle** |
| `board_hide_hours` | `24` | the board hides sessions with no event for this long |
| `board_interval` | `30` | seconds between board heartbeats (the *for* column ticks); a state change redraws immediately regardless |

## The session board

```sh
iriscale-voice sessions            # one frame: every live session, state, how long, what was last said
iriscale-voice board               # live; redraws only when a session changes state; q quits
iriscale-voice board --interval 10 # heartbeat every 10 s instead of 30
```

State comes from one small file per session in `~/.claude/iriscale-voice-sessions/`,
written by the same script on every hook event — so any agent that calls it feeds the
board. States: **needs your answer** (permission prompt) · **ready** for review ·
working · waiting · error · idle. A small window off to the side, on Windows Terminal:

```
wt -w iriscale --size 64,18 --pos 1180,80 --title sessions iriscale-voice board
```

## Session names

The spoken name is, in order: the session's `/rename` name → the working-directory
folder name → "Claude". Underscores and hyphens are spoken as spaces
(`iriscale_voice` → "iriscale voice"). So `/rename` your sessions and you'll know
which terminal is talking.

## Command line

The command is named after the product: **`iriscale-voice`**. It's the same script the
hooks call. `--help` is the source of truth; the table above is kept in sync with
`config list` by a test.

```sh
iriscale-voice --help              # all commands
iriscale-voice status              # what's configured, what will speak
iriscale-voice config list         # every key: current value, default, meaning
iriscale-voice config get preset
iriscale-voice config set preset basic
iriscale-voice config unset quiet_hours
iriscale-voice config path         # where the file is
iriscale-voice events              # every event, when it fires, what it says
iriscale-voice presets
iriscale-voice test                # speak a test phrase
iriscale-voice --version
```

**Inside Claude Code** you don't need any of this — `/iriscale-voice:<command>` runs the same
thing (`/iriscale-voice:config list`, `/iriscale-voice:preset basic`, `/iriscale-voice:help`).

**Outside Claude Code** (other agents, scripts, or just preference), put it on your PATH
once. The plugin installs it at
`~/.claude/plugins/cache/iriscale/iriscale-voice/<version>/bin/iriscale-voice`; from a
git checkout it's `bin/iriscale-voice`.

```sh
# macOS / Linux
ln -s "$(pwd)/bin/iriscale-voice" ~/.local/bin/iriscale-voice
# Windows (Git Bash)
ln -s "$(pwd)/bin/iriscale-voice" /usr/bin/iriscale-voice      # or any dir on PATH
```

Then `iriscale-voice --help` works anywhere. Until you do that, `sh bin/iriscale-voice …`
from the checkout works too.

## Debugging

```sh
IRISCALE_VOICE_DEBUG=1 sh bin/iriscale-voice Stop < payload.json   # prints the decision, never speaks
tail ~/.claude/iriscale-voice.log                             # what actually fired
```

`test/run.sh` fires every event through every preset in debug mode.
