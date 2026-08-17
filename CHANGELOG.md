# Changelog

All notable changes to iriscale_voice. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [SemVer](https://semver.org/). Every entry links the PR that shipped it.

## [Unreleased]

## [0.1.3] — 2026-08-17

### Fixed
- **`/voice` did nothing — it's a Claude Code built-in.** Claude Code has its own `/voice`
  (dictation mode: hold / tap / off), and built-ins shadow a plugin's short-form command
  name, so `/voice help` toggled dictation instead of reaching us. The slash command is now
  **`/iriscale-voice`** (`/iriscale-voice help`, `/iriscale-voice config list`, …) —
  same name as the plugin and the CLI, no collision. If you ran the bare `/voice` while
  this was broken, Claude Code's dictation mode is now on: `/voice off` turns it back off.
- Test added: no bundled command may share a name with a Claude Code built-in.

## [0.1.2] — 2026-08-16

### Added
- **The command is now `iriscale-voice`** (was `bin/notify.sh`). Named after the product,
  no extension, executable bit set — like `gh` or `claude`. `/voice` (fully
  `/iriscale-voice:voice`), the plugin `iriscale-voice`, and the command `iriscale-voice`
  now all share one name. Docs cover putting it on PATH for use outside Claude Code.
- **Standard command-line interface** on `bin/iriscale-voice`: `--help`/`-h`, `--version`/`-V`,
  `status`, `config list` (every key with current value, default and meaning),
  `config get|set|unset|path|edit`, `events`, `presets`, `say`, `test`, `mute`,
  `unmute`. Unknown commands exit 2 with usage. `/voice` maps onto it 1:1.
- `docs/PLATFORMS.md`: support matrix for 14 other coding agents (Codex CLI, Copilot CLI,
  Grok Build, Gemini CLI, Junie, Cursor, Devin, OpenCode/Kilo, Windsurf, Cline, Aider,
  Amp, Kiro, and the ones with no hook system), with adapter plan and effort per agent
  (#1).
- `CHANGELOG.md` and a documented release process in `CONTRIBUTING.md` (#1).
- Tests: CLI behaviour, and a guard that the version in `bin/notify.sh`, `plugin.json`
  and `marketplace.json` agree; every `config list` key must be documented in
  `docs/CONFIG.md`. 72 checks.

### Changed
- **Versioning policy:** every release bumps the patch number (0.1.1 → 0.1.2 → …) —
  small, frequent, visible releases. Roadmap re-numbered accordingly with a per-release
  plan through 0.1.12.

## [0.1.1] — 2026-08-16

### Fixed
- **Repeated announcements.** A looping subagent fired `SubagentStop` every ~32 s and
  every one was spoken. New `repeat_cooldown` setting (default 60 s): the same line for
  the same session inside the window is spoken once. `repeat_cooldown=0` disables.
- **"soob-agent".** TTS engines read "subagent" as one word; it now says "sub agent done".
- Root cause of the loop being audible at all was a leftover `event.SubagentStop=on`
  written to the live config by an early test run — the test harness now uses a
  throwaway config dir and can no longer touch `~/.claude/iriscale-voice.conf`.

### Verified
- `idle_prompt` Notification matcher and `PermissionRequest` both observed firing live
  (previously written to docs only).

## [0.1.0] — 2026-08-15

First release as a Claude Code plugin.

### Added
- `bin/notify.sh`: one zero-dependency POSIX script for every hook event. Speaks via
  System.Speech (Windows), `say` (macOS), `spd-say`/`espeak`/`notify-send` (Linux).
- Presets `off | basic | standard | verbose`, per-event overrides, quiet hours,
  mute/only session lists, minimum turn length, concurrent-session lock, activity log.
- `PermissionRequest` speaks the tool or shell command ("wants to run git push");
  `StopFailure` speaks the reason ("stopped: rate limit"); long turns get elapsed time.
- `/voice` slash command: `status | test | preset | mute | unmute | quiet | set | say`.
- Repo is its own marketplace: `/plugin marketplace add justbuild-it/iriscale_voice`.
- `test/run.sh` (41 checks), `docs/CONFIG.md`, `docs/ROADMAP.md`.
- `.gitattributes` forcing LF so the script survives Windows checkouts.

### Fixed
- Session-name lookup took the last `"name":` in the session file — inside `formerNames`
  — so any `/rename`d session spoke its old name.

### Removed
- `userConfig` block from `plugin.json`: it made the CLI nag on every install.

[Unreleased]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/justbuild-it/iriscale_voice/releases/tag/v0.1.0
