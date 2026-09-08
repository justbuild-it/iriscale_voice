---
name: iriscale-voice
description: Install, diagnose, and manage iriscale voice notifications. Use when the user asks about voice alerts, iriscale voice status, testing, muting, presets, configuration, the session board, Codex hook setup, installation, updating, uninstallation, or why an agent did not speak.
---

# iriscale voice

Run requested read-only commands immediately; ask before commands that change
installation or user configuration.

## Which interface you are in

- **Claude Code, plugin install**: use the slash commands `/iriscale-voice:status`,
  `:test`, `:preset <basic|standard|verbose|off>`, `:mute`, `:unmute`,
  `:quiet <start-end|off>`, `:config <list|get|set|unset|path>`, `:help`. The same CLI is
  at `${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice` for anything else (`sessions`, `board`,
  `focus`).
- **Claude Code, npm install** (`npx iriscale-voice@latest install claude --apply`): the
  same commands are flat and hyphenated - `/iriscale-voice-status`, `/iriscale-voice-test`,
  `/iriscale-voice-preset` - and `iriscale-voice doctor claude` diagnoses the setup.
- **Codex** or a plain shell: use the `iriscale-voice` CLI on PATH. If it is missing,
  install it on any OS with `npx iriscale-voice@latest install codex --apply`
  (Windows without Node: the PowerShell one-liner in the README).

## Commands

- Inspect: `iriscale-voice status`, `iriscale-voice sessions`, `iriscale-voice doctor codex`,
  `iriscale-voice config list`
- Test: `iriscale-voice test` (Windows: also reports PowerShell's Volume Mixer level; `test --fix` restores it to 100%)
- Control: `iriscale-voice mute`, `iriscale-voice unmute`,
  `iriscale-voice config set <key> <value>`
- Board: `iriscale-voice board` (live pane; click or press a row number to raise that
  session's window; `q` quits)
- Install (any OS, needs Node 18+): `npx iriscale-voice@latest install codex --apply`;
  without `--apply` it writes nothing and prints the config to paste. Lifecycle:
  `iriscale-voice update`, `iriscale-voice uninstall codex`
- Discover: `iriscale-voice --help`

## Why didn't it speak?

1. `iriscale-voice status` - is `enabled` true, is the event in the preset, quiet hours?
2. `tail ~/.claude/iriscale-voice.log` - did the event arrive at all?
3. Codex: `iriscale-voice doctor codex`, then `/hooks` in Codex must show `Installed 1`
   and `Active 1` for `UserPromptSubmit` and `PermissionRequest`; restart Codex after
   changing hooks.
