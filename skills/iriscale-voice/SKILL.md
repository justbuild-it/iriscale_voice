---
name: iriscale-voice
description: Install, diagnose, and manage iriscale voice notifications. Use when the user asks about voice alerts, iriscale voice status, testing, muting, presets, configuration, the session board, Codex hook setup, installation, updating, uninstallation, or why an agent did not speak.
---

# iriscale voice

Run requested read-only commands immediately; ask before commands that change
installation or user configuration.

## Which interface you are in

- **Claude Code** (this skill loaded from the plugin): use the slash commands
  `/iriscale-voice:status`, `:test`, `:preset <basic|standard|verbose|off>`, `:mute`,
  `:unmute`, `:quiet <start-end|off>`, `:config <list|get|set|unset|path>`, `:help`.
  The same CLI is at `${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice` for anything else
  (`sessions`, `board`, `focus`).
- **Codex** or a plain shell: use the `iriscale-voice` CLI on PATH. If it is missing on
  Windows, the one-line installer is in the README; on macOS/Linux, `docs/install/codex.md`.

## Commands

- Inspect: `iriscale-voice status`, `iriscale-voice sessions`, `iriscale-voice doctor codex`,
  `iriscale-voice config list`
- Test: `iriscale-voice test`
- Control: `iriscale-voice mute`, `iriscale-voice unmute`,
  `iriscale-voice config set <key> <value>`
- Board: `iriscale-voice board` (live pane; click or press a row number to raise that
  session's window; `q` quits)
- Install (Windows): `iriscale-voice install codex --apply`; lifecycle: `iriscale-voice
  update`, `iriscale-voice uninstall codex`
- Discover: `iriscale-voice --help`

## Why didn't it speak?

1. `iriscale-voice status` - is `enabled` true, is the event in the preset, quiet hours?
2. `tail ~/.claude/iriscale-voice.log` - did the event arrive at all?
3. Codex: `iriscale-voice doctor codex`, then `/hooks` in Codex must show `Installed 1`
   and `Active 1` for `UserPromptSubmit` and `PermissionRequest`; restart Codex after
   changing hooks.
