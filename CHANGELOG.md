# Changelog

All notable changes to iriscale_voice. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [SemVer](https://semver.org/). Every entry links the PR that shipped it.

## [Unreleased]

### Added
- `docs/PLATFORMS.md`: support matrix for 14 other coding agents (Codex CLI, Copilot CLI,
  Grok Build, Gemini CLI, Junie, Cursor, Devin, OpenCode/Kilo, Windsurf, Cline, Aider,
  Amp, Kiro, and the ones with no hook system), with adapter plan and effort per agent.
- `CHANGELOG.md` (this file) and a documented release process in `CONTRIBUTING.md`.

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

[Unreleased]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/justbuild-it/iriscale_voice/releases/tag/v0.1.0
