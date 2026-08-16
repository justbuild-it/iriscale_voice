---
description: Configure iriscale voice notifications. Usage: /voice [status|test|help|preset <basic|standard|verbose|off>|mute|unmute|quiet <start-end|off>|config list|config get <key>|config set <key> <value>|config unset <key>|events|presets|say <text>]
disable-model-invocation: true
allowed-tools: Bash(sh *)
---

The user ran `/voice $ARGUMENTS` to configure their spoken Claude Code notifications.
Apply it by running the plugin's CLI — do not edit files by hand.

CLI: `sh "${CLAUDE_PLUGIN_ROOT}/bin/notify.sh" <command> [args]` — it has standard
help; when unsure run `sh "${CLAUDE_PLUGIN_ROOT}/bin/notify.sh" --help`.

Map the arguments (first word is the action; pass the rest through unchanged):

| User typed | Run |
|---|---|
| *(nothing)* or `status` | `... status` |
| `help` | `... --help` |
| `test` | `... test` — speaks a test phrase out loud |
| `preset <name>` | `... config set preset <name>` — `basic`, `standard`, `verbose`, or `off` |
| `mute` / `unmute` | `... mute` / `... unmute` |
| `quiet <start>-<end>` (24h, e.g. `22-8`) | `... config set quiet_hours <start>-<end>` |
| `quiet off` | `... config unset quiet_hours` |
| `config list` / `config` | `... config list` — every setting with current value, default, meaning |
| `config get <key>` | `... config get <key>` |
| `config set <key> <value>` / `set <key> <value>` | `... config set <key> <value>` |
| `config unset <key>` | `... config unset <key>` |
| `events` | `... events` — every event, when it fires, what it says |
| `presets` | `... presets` |
| `say <text>` | `... say <text>` |

After running it, show the command's output verbatim, then one line on what changed.
If the user asks what the presets mean, run `... presets` and add:

- **basic** — speaks when a turn finishes and when Claude is waiting for you. Nothing else.
- **standard** — basic + errors (rate limit, billing, auth) + "wants to run <command>" on permission prompts. Silent on turns under 30 s.
- **verbose** — everything, including subagents and session end.
- **off** — silent, but stays installed.

If `$ARGUMENTS` is unrecognized, run `... --help` and show it. Never invent settings;
only keys that `config list` prints.
