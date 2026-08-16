# Configuration

Most people never need this page. Pick a preset with `/voice preset basic` and you're
done. Everything below is for tuning.

## Where settings live

`~/.claude/iriscale-voice.conf` — plain `key=value`, one per line, `#` for comments.
Created on first `/voice` command; safe to edit by hand; re-read on every event, so
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
| `enabled` | `true` | `false` = silent. `/voice mute` sets this |
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

## Session names

The spoken name is, in order: the session's `/rename` name → the working-directory
folder name → "Claude". Underscores and hyphens are spoken as spaces
(`iriscale_voice` → "iriscale voice"). So `/rename` your sessions and you'll know
which terminal is talking.

## Debugging

```sh
IRISCALE_VOICE_DEBUG=1 sh bin/notify.sh Stop < payload.json   # prints the decision, never speaks
sh bin/notify.sh status                                       # what's configured
sh bin/notify.sh test                                         # speak a test phrase
tail ~/.claude/iriscale-voice.log                             # what actually fired
```

`test/run.sh` fires every event through every preset in debug mode.
