# Changelog

All notable changes to iriscale_voice. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [SemVer](https://semver.org/). Every entry links the PR that shipped it.

## [Unreleased]

## [0.1.17] — 2026-09-03

Release-readiness pass: two independent reviews (security/robustness, docs/UX) plus
CI. Nothing here changes what the voice says for `done` / `waiting` / `error`.

### Security & privacy
- **Permission prompts scrub credentials before speaking or logging.** The command is
  still spoken (up to 60 characters - that is the point of the announcement), but words
  that look like secrets are replaced with "redacted": `Bearer …`, `sk-…`, `ghp_…`,
  `AKIA…`, `password=…`, `user:pass@host` in URLs, and the value after `--token`,
  `--password`, `-p`, `--api-key`. New setting `command_detail`: `redacted` (default),
  `program` (program + first word only, for shared spaces), `full` (verbatim). The old
  behaviour put secrets on the speaker and in a plaintext log unconditionally.
- Session ids are restricted to `[A-Za-z0-9._-]` before they become file names (they are
  written under the state dirs and `rm -f`'d on `SessionEnd`; a crafted id could escape).
- State and scratch directories are created mode 700 (`/tmp` can be shared).
- `clean()`'s allowlist is now a documented, tested invariant: it can never admit
  `' " \ ` $`, which is what keeps the PowerShell speech command safe.
- Config values used in the speech command are validated (`volume`/`rate` numeric,
  `voice` restricted); `config set` rewrites with builtins so `| & \` in values can no
  longer corrupt the file; keys must be `[A-Za-z0-9._]`.
- The activity log rolls at 1 MB.
- `install.ps1` validates `hooks.json` before touching anything, reports which steps
  completed if it fails midway, and installs from the **release tag matching the
  installer** (`-Ref`, default `v0.1.17`) instead of the moving `main`. `SECURITY.md`
  explains what the tool touches and how to install with inspection.

### Fixed
- **`/iriscale-voice:config …` was broken since 0.1.4** — the command file ran a garbled
  shell line. `/iriscale-voice:config list` etc. work again.
- `docs/install/codex.md` showed Windows paths with backslashes, which are invalid TOML/
  JSON escapes; copy-pasting corrupted `config.toml`/`hooks.json`. Forward slashes now.
- The bundled skill is host-aware: in Claude Code it points at the slash commands and the
  plugin's own CLI path; it no longer tells macOS users to run a Windows installer.
- `board` on a strict POSIX `sh` (dash) had dead keys; it now re-executes itself under
  bash/zsh when available and says so otherwise.
- `jget` honours JSON escapes, so a command containing quotes is read whole instead of
  being cut at the first `\"`.
- `notify-send` title is "iriscale voice", not "Claude Code".
- Timing guard for non-blocking speech relaxed to 2 s (the bug it guards was 7 s); it
  flaked on a slow run.

### Added
- **CI**: `.github/workflows/test.yml` runs the suite on Ubuntu (dash + bash), macOS
  (`sh`) and Windows (Git Bash), checks the four version manifests agree, and parses the
  JSON. First time macOS/Linux run the suite at all.
- `.gitignore`, `SECURITY.md`.

### Docs
- Honest platform claims: verified on Windows; macOS/Linux run the same POSIX script and
  pass CI but the speech backends there are untested by the maintainers. Click-to-focus
  is Windows (+ Linux with `wmctrl`), not macOS.
- README reordered for Claude Code first; upgrading covers both install paths; the
  board is no longer listed as future work.
- `docs/PLATFORMS.md` status column says "planned" instead of fictitious versions;
  `docs/ROADMAP.md` release table de-duplicated and renumbered; CONTRIBUTING describes
  the guard tests that actually exist and adds "update the README's pinned install URL"
  to the release steps.

## [0.1.16] — 2026-08-28

### Changed
- Board header clock is labelled: `updated 15:32:38`. It is the time of the last repaint
  (a state change or the `board_interval` heartbeat), not a live clock.
- Decision recorded in the roadmap: selecting the terminal *tab* inside an IDE is out of
  scope. Real setups run several IDE windows across screens, each with several tabs; the
  board raises the right window and names the tab, and stops there.

## [0.1.15] — 2026-08-28

### Fixed
- **Focus is fast**: ~3 s → well under 1 s. One WMI query for the process table instead
  of one per ancestor hop, and `WScript.Shell.AppActivate` instead of an `Add-Type`
  compile on every click. Keys act immediately: the board reads one character at a time
  instead of waiting a second for more.
- **Focus says what happened.** When the session lives in a tab of a multi-session host
  (Devin, VS Code, Windsurf, Cursor, Windows Terminal) the note now reads *"Devin is in
  front - it hosts several sessions, so pick the terminal tab named 'geo.3'"* instead of
  claiming success that changed nothing visible. That was the "pressing 3 found nothing"
  report: all rows resolved to the same already-front IDE window.
- Board header shows the version; footer fits 80 columns.

## [0.1.14] — 2026-08-28

### Added
- **Click a session on the board to bring it to the front.** `board` now numbers its
  rows, reports mouse clicks (SGR 1006), and on a click or a digit key raises that
  session's window: it walks up from the session's pid to the first ancestor that owns a
  window - the terminal or IDE hosting it. Exact for sessions in their own windows; for
  tabs inside one host (Windows Terminal, Devin, VS Code) it raises the host and the
  highlighted row tells you which tab. Windows implemented; Linux via `wmctrl` if present;
  macOS says "not implemented yet" (agents there don't yet expose a usable pid chain).
- `iriscale-voice focus <row|name|pid>` as a standalone command (what the board calls).
- Board footer explains the keys; terminal state (raw mode, mouse reporting, cursor) is
  restored on exit.

## [0.1.13] — 2026-08-28

### Fixed
- **`iriscale-voice update` (and `uninstall`) never worked through the Windows launcher.**
  The launcher runs `bin\iriscale-voice` in bash, which keeps the file open; the
  installer then tried to overwrite that same file and Windows refused ("being used by
  another process"). Both commands now detach the installer so the launcher exits first
  (progress in `$TMP/iriscale-voice/update.log`), and the installer stages the new
  script as `.new` and swaps it with retries instead of failing outright. Workaround
  for 0.1.9–0.1.12: re-run the one-liner (`irm … | iex`) directly.
- Release checklist: verify `HEAD == origin/main` and the version string before
  tagging — the v0.1.12 tag was cut from a stale local main after a failed pull, and
  the tag ruleset (correctly) makes tags immovable. See CONTRIBUTING.

## [0.1.12] — 2026-08-28

### Fixed
- **Board colours printed as text** (`[32m*[0m`): the `ESC` variable that every colour
  and cursor sequence is built from was never defined in 0.1.11, so each sequence lost
  its first byte. Defined now. `sessions --color` forces colour when stdout is not a
  terminal (tests use it); a test asserts the colour path emits real escape bytes and
  `--plain` emits none - the gap that let 0.1.11 through.

## [0.1.11] — 2026-08-28

### Added
- **Session board.** `iriscale-voice sessions` prints every live session with its state
  (needs your answer / ready / working / waiting / error / idle), how long it has been
  there, which agent, and what was last said. `iriscale-voice board` is the live version
  for a terminal pane or a small Windows Terminal window off to the side: it **redraws
  only when a session changes state** (plus a heartbeat so ages tick), overwrites in
  place with no flicker, and shows a colour legend. `q` quits.
- **Session state layer**, the piece that makes the board agent-independent: on every
  hook event the script writes one key=value file per session to
  `~/.claude/iriscale-voice-sessions/` (agent, name, status, since, pid, cwd, last
  said). Builtins only; hook latency unchanged. Claude sessions that predate this
  version are synthesized from `~/.claude/sessions` so nothing is missing on first run.
- Settings: `board_ready_minutes`, `board_hide_hours`, `board_interval`.
- Design note with the measured options: `docs/design/status-board.md` (#13).

### Not yet
- Click-to-focus (next release): mouse reporting in the pane, raise-by-pid for
  sessions in their own windows, host window otherwise.

## [0.1.10] — 2026-08-19

### Fixed
- **0.1.9 installer wrote hooks Codex ignores.** `install.ps1` emitted only `commandWindows`;
  Codex requires the portable `command` field to exist (the Windows override alone shows
  as `Installed 0`). The installer now writes both. `doctor codex` flags hooks missing
  `command`; tests cover installer output and the doctor check. Re-run the installer
  (or `iriscale-voice update`) to repair an existing install.

## [0.1.9] — 2026-08-18

### Added
- One-command Windows Codex installer with a stable launcher, user `PATH`, PowerShell
  tab completion, idempotent configuration merging, backups, update, and uninstall.
- Codex plugin manifest and `$iriscale-voice` skill for discoverable status,
  diagnostics, testing, and configuration commands.
- `iriscale-voice completions powershell|bash|zsh`, `?` help, `install codex --apply`,
  `update`, and `uninstall codex` CLI surfaces.

## [0.1.8] — 2026-08-18

### Fixed
- **Codex hooks failed with "date: command not found".** `install codex` printed the
  shell that `command -v sh` resolves to - Git's RAW MSYS `usr/bin/sh.exe`, which
  gets no `/usr/bin` on PATH when launched directly by a Windows process, so `date`,
  `uname`, `mkdir` and `tr` were all missing. It now prefers the `bin/sh.exe` WRAPPER,
  which sets PATH up. (The hand-tested notify line already used the wrapper - that is
  why turn announcements worked while the regenerated hooks failed.)
- **Degraded-environment hardening**, so a PATH-less launch can never error or
  mis-fire again: `os()` answers from Windows' own `$OS` variable without spawning
  `uname`; a dead clock skips quiet hours instead of reading as midnight (which
  silently suppressed everything inside a wrapping window); min-turn and cooldown
  gates disengage rather than misfire; `clean()` falls back to a builtin scrub
  instead of speaking an empty string.
- Tests: dead-clock, `$OS` detection, and "install codex must never print the raw
  usr/bin sh" guards. 110 checks.

## [0.1.7] — 2026-08-18

### Fixed
- Codex `PermissionRequest` and `UserPromptSubmit` hooks are now synchronous because
  Codex 0.147 skips asynchronous hook definitions, leaving them at `Installed 0`.
- Permission announcements now explicitly say the session is waiting for an answer.

### Added
- `iriscale-voice doctor codex` performs a read-only check for missing Codex notify or
  hook configuration and the unsupported `async: true` form.
- **Speech no longer blocks the calling host.** The speaker runs in a detached
  background subshell; the hook returns in ~0.4 s instead of ~7 s. Required for Codex,
  whose hooks are synchronous - it froze for the whole spoken phrase before showing a
  permission prompt. Guard test: with 3 s speaker stubs the hook must return within 1 s.

## [0.1.6] — 2026-08-18

### Added
- **Codex CLI support** (`docs/install/codex.md`), verified live on Codex 0.147.0:
  - `notify` mode: `iriscale-voice notify` takes the turn JSON from the last argument
    (also accepts bare JSON as `$1`); `agent-turn-complete` → done. One `config.toml`
    line, no hook-trust prompts.
  - Codex `/rename` names read from `~/.codex/session_index.jsonl` (`thread-id` →
    `thread_name`), same as Claude's `/rename`.
  - Optional two-hook `hooks.json` for `PermissionRequest` + turn-start stamp.
  - `iriscale-voice install codex` prints both configurations with absolute paths and
    never edits Codex configuration.
- **Alias layers** (first slice of multi-agent support): session id from `session_id` |
  `thread-id` | `sessionId` | `conversation_id`; events `agentStop`/`AfterAgent`/
  `TaskComplete`/`session.idle`/`post_cascade_response` → Stop, `errorOccurred`/
  `session.error`/`TaskCancel` → StopFailure, `permissionRequest`/`permission.asked` →
  PermissionRequest.
- `docs/install/` — one page per agent.
- Synthetic alias coverage for Copilot (`sessionId`, done/error), Gemini (`AfterAgent`),
  and Cursor (`stop` status plus `workspace_roots`).

## [0.1.5] — 2026-08-17

### Changed
- **5× faster on Windows.** Every hook event ran ~1.5–1.8 s of shell before speaking,
  because each config lookup spawned `sed | tail | tr` and each JSON field `grep | head |
  sed` — ~40 external processes at 25–50 ms each on MSYS. The config file is now read once
  into memory, and every lookup, JSON field, path basename and name-cleanup step uses
  shell builtins only. Hook path 1479 → 283 ms (best of 5); `status` 1739 → 455 ms;
  test suite 82 → 26 s. macOS/Linux fork cheaply so gain less, but still run fewer
  processes.
- Test guard: the hook path may spawn at most one text-processing tool (`sed`, `grep`,
  `tr`, `awk`, `cut`, `head`, `tail`, `cat`, `find`), measured with PATH shims. 89 checks.

## [0.1.4] — 2026-08-17

### Fixed
- **Slash commands are now one per subcommand, under the plugin namespace:**
  `/iriscale-voice:status`, `:test`, `:help`, `:preset <name>`, `:mute`, `:unmute`,
  `:quiet <start-end|off>`, `:config <list|get|set|unset|path>`. Type `/iriscale-voice:` and
  autocomplete lists them. 0.1.3 had a single command file named like the plugin, which
  Claude Code exposed as `/iriscale-voice:iriscale-voice` — technically present, unusable.
- README "Upgrading": after `/plugin marketplace update iriscale`, **restart Claude Code** —
  `/reload-plugins` re-reads the plugin directory the session started with, so new or
  renamed commands only appear after a restart.
- Test guard replaced: docs may never mention a bare `/<command>`; always the namespaced
  form. Suite calls `status` once per preset instead of once per event (still slow on
  Windows — process-spawn cost in `cfg`; fix is next release). 88 checks.

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

[Unreleased]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.17...HEAD
[0.1.17]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.16...v0.1.17
[0.1.16]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.15...v0.1.16
[0.1.15]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.14...v0.1.15
[0.1.14]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.13...v0.1.14
[0.1.13]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.12...v0.1.13
[0.1.12]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/justbuild-it/iriscale_voice/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/justbuild-it/iriscale_voice/releases/tag/v0.1.0
