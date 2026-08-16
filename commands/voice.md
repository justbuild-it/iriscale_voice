---
description: Configure iriscale voice notifications — preset, mute, quiet hours, test. Usage: /voice [status|test|preset <basic|standard|verbose|off>|mute|unmute|quiet <start-end|off>|set <key> <value>]
disable-model-invocation: true
allowed-tools: Bash(sh *)
---

The user ran `/voice $ARGUMENTS` to configure their spoken Claude Code notifications.
Apply it by running the plugin's CLI — do not edit files by hand.

Script: `sh "${CLAUDE_PLUGIN_ROOT}/bin/notify.sh" <subcommand>`

Map the arguments like this (first word is the action):

| User typed | Run |
|---|---|
| *(nothing)* or `status` | `... status` |
| `test` | `... test` — speaks a test phrase out loud |
| `preset <name>` | `... set preset <name>` — name is one of `basic`, `standard`, `verbose`, `off` |
| `mute` / `unmute` | `... mute` / `... unmute` |
| `quiet <start>-<end>` (24h hours, e.g. `22-8`) | `... set quiet_hours <start>-<end>` |
| `quiet off` | `... set quiet_hours ""` |
| `set <key> <value>` | `... set <key> <value>` — any key from docs/CONFIG.md |
| `say <text>` | `... speak "<text>"` |

After running it, show the command's output verbatim, then one line on what changed.
If the user asks what the presets mean:

- **basic** — speaks when a turn finishes and when Claude is waiting for you. Nothing else. (What most people want.)
- **standard** — basic + errors (rate limit, billing, auth) + "wants to run <command>" on permission prompts. Silent on turns under 30 s so it isn't chatty while you're watching.
- **verbose** — everything, including subagents and session end.
- **off** — silent, but stays installed.

If `$ARGUMENTS` is unrecognized, print the usage line from the description and stop.
Never invent settings; only keys that `notify.sh status` prints or that docs/CONFIG.md lists.
