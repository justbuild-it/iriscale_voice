---
name: iriscale-voice
description: Install, diagnose, and manage Iriscale Voice notifications. Use when the user asks about voice alerts, Iriscale Voice status, testing, muting, presets, configuration, Codex hook setup, installation, updating, uninstallation, or why an agent did not speak.
---

# Iriscale Voice

Use the installed `iriscale-voice` CLI. Run requested read-only commands immediately;
ask before commands that change installation or user configuration.

## Commands

- Inspect: `iriscale-voice status`, `iriscale-voice doctor codex`, `iriscale-voice config list`
- Test: `iriscale-voice test`
- Control: `iriscale-voice mute`, `iriscale-voice unmute`, `iriscale-voice config set <key> <value>`
- Install: `iriscale-voice install codex --apply`
- Lifecycle: `iriscale-voice update`, `iriscale-voice uninstall codex`
- Discover: `iriscale-voice --help`

If the executable is unavailable, tell the user to run the repository's `install.ps1`
on Windows. Do not substitute Claude Code's `/iriscale-voice:*` commands; those are a
different host interface.

After changing Codex hooks, tell the user to restart Codex and confirm `/hooks` shows
`Installed 1` and `Active 1` for `UserPromptSubmit` and `PermissionRequest`.
