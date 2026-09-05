# Roadmap

Tracking every capability proposed for iriscale_voice, its status, and the reasoning.
Update this file when something ships or gets cut. Order within a tier is priority.

Legend: `[x]` shipped · `[~]` in progress · `[ ]` planned · `[-]` cut (reason given)

## Release plan (patch-per-release; see CONTRIBUTING.md)

Each release is small and ships as soon as it's done. Target contents, in order:

| Version | Contents | Status |
|---|---|---|
| 0.1.0 | Plugin, presets, slash command, Win/mac/Linux speakers, tests | shipped 2026-08-15 |
| 0.1.1 | Repeat guard, "sub agent" pronunciation | shipped 2026-08-16 |
| 0.1.2 | Standard CLI (`--help`, `config list/get/set/unset/path`, `events`, `presets`, `--version`); command renamed `iriscale-voice`; patch-per-release policy; version-consistency test | shipped 2026-08-16 |
| 0.1.3 | Fix: slash command renamed `/voice` → `/iriscale-voice` (`/voice` is a Claude Code built-in) | shipped 2026-08-17 |
| 0.1.4 | Fix: one command file per subcommand → `/iriscale-voice:status` etc.; upgrade/restart note | shipped 2026-08-17 |
| 0.1.5 | Perf: builtins-only hook path (Windows 1479 → 283 ms per event; suite 82 → 26 s); spawn-count guard | shipped 2026-08-17 |
| 0.1.6 | Codex CLI (notify + optional hooks, /rename support) + alias layers | shipped 2026-08-18 |
| 0.1.7 | Codex sync hooks; non-blocking speech; `doctor codex`; "waiting for your answer" phrasing | shipped 2026-08-18 |
| 0.1.8 | Codex hooks: Git wrapper sh.exe; degraded-env hardening | shipped 2026-08-18 |
| 0.1.9 | One-command Windows installer, stable launcher, PATH, completion, Codex skill, update/uninstall | shipped 2026-08-19 |
| 0.1.10 | Installer writes required `command` field (hooks loaded as Installed 0 before) | shipped 2026-08-19 |
| 0.1.11 | Session board: agent-independent state layer + `sessions` / `board` (redraw on change, colour legend) | shipped 2026-08-28 |
| 0.1.12 | Fix: board colours (ESC undefined); colour path tested | shipped 2026-08-28 |
| 0.1.13 | Fix: `update`/`uninstall` via the launcher (self-overwrite); verified-tag release checklist | shipped 2026-08-28 |
| 0.1.14 | Board click-to-focus: mouse reporting, raise-by-pid, host window when tabbed | shipped 2026-08-28 |
| 0.1.15 | Focus 3 s → 1.4 s; honest note for tabbed hosts; version in header | shipped 2026-08-28 |
| 0.1.16 | Board clock labelled "updated"; tab selection declared out of scope | shipped 2026-08-28 |
| 0.1.17 | Release-readiness: privacy default for permission prompts, id sanitising, mode-700 state dirs, log rotation, pinned installer, CI on Ubuntu/macOS/Windows, SECURITY.md, docs reconciled | this PR |
| 0.1.18 | The board keeps itself open (`board_autostart`, `board --open`, `/iriscale-voice:board`); dead sessions forgotten; `forget` | shipped 2026-09-04 |
| 0.1.19 | `update` moves to the latest release (it re-installed the pinned one) | shipped 2026-09-04 |
| 0.1.20 | `test` reads PowerShell's Volume Mixer level on Windows (0% = silent everywhere); `test --fix` | this PR |
| 0.1.21 | Copilot CLI + Grok Build + Gemini CLI install snippets | planned |
| 0.1.22 | Speak a one-line summary of what was done (from `transcript_path`) | planned |
| 0.1.23 | Escalate unanswered permission prompts (3 min, 10 min) | planned |
| 0.1.24 | Junie, Cursor, Devin, OpenCode/Kilo adapters | planned |
| 0.1.25 | Toast / Notification Center / notify-send alongside speech; earcons mode | planned |
| 0.1.26 | Per-session voice signatures; stamp housekeeping | planned |
| 0.1.27 | Windows-without-Git-Bash PowerShell fallback | planned |
| 0.1.28 | Windsurf, Cline, Aider (done-only) | planned |
| later | macOS/Linux bar plugins; Windows tray (opt-in); macOS/Linux live verification as users report | |
| out of scope | **Selecting the terminal tab inside an IDE.** Real setups run several IDE windows across screens, each with several terminal tabs; IDE tabs are not addressable from outside. The board raises the correct window and names the tab. Windows Terminal tabs via UI Automation remains a possible opt-in if sessions run there. | decided 2026-08-28 |

Numbers beyond the next release are intent, not promises — anything a user reports
as broken jumps the queue.

## Origin

Started 2026-08-14 as a single Windows PowerShell hook (`speak-notify.ps1`) that spoke
"<session> done" / "<session> needs input". Rebuilt the same day with presets, then
re-scoped as a cross-platform Claude Code plugin for open-source release.

## Tier 0 — Release blockers (shipped 0.1.0–0.1.10)

- [x] **Package as a Claude Code plugin** so users install with two commands
      instead of hand-editing `settings.json`. Repo doubles as its own marketplace
      (`.claude-plugin/plugin.json` + `marketplace.json`, `hooks/hooks.json`).
      _Verified end-to-end via `claude plugin install` the same day._
- [x] **Cross-platform speaker** in `bin/iriscale-voice`: Windows (`powershell.exe` +
      System.Speech), macOS (`say`), Linux (`spd-say` → `espeak-ng` → `espeak` →
      `notify-send` → bell). Zero external dependencies — no `jq`, `node`, or
      `python`. Verified 2026-08-15 that `jq` is absent even on a dev machine and
      Windows `python3` can be a Store stub. _Windows backend tested audibly; macOS
      and Linux backends written to spec but untested — need a run on each._
- [x] **Zero-config default**: no config file → `standard` preset.
- [x] **One-line config**: `~/.claude/iriscale-voice.conf`, `key=value`, outside the
      plugin dir. Also honors the plugin's `userConfig` (`CLAUDE_PLUGIN_OPTION_PRESET`).
- [x] **`/iriscale-voice` slash command** (`commands/iriscale-voice.md`) → `/iriscale-voice`,
      bare `/iriscale-voice` when no conflict: `status`, `test`, `preset`, `mute`, `unmute`,
      `quiet`, `set`, `say`. Drives the script's CLI subcommands.
- [x] **README** with the two-command install and presets. _GIF/asciinema still to do._
- [x] **Test script** `test/run.sh` — every event × every preset, CLI, installer, security guards; run in CI on Ubuntu (dash + bash), macOS and Windows.
- [~] **Verify a real install.** Done 2026-08-15 via the `claude plugin` CLI:
      `validate` passes, `marketplace add <local path>` + `install iriscale-voice@iriscale`
      succeed, `"source": "./"` works, all 7 hook events and the `voice` skill resolve,
      installed copy runs from `~/.claude/plugins/cache/iriscale/iriscale-voice/0.1.0/`
      through Git Bash with a Windows-style `${CLAUDE_PLUGIN_ROOT}`. Old
      `speak-notify.ps1` hooks removed from `settings.json` (backup
      `settings.json.20260815-pre-plugin.bak`). Always-on cost: ~97 tokens/session.
      _Observed live 2026-08-16 in `iriscale-voice.log`: `idle_prompt` matcher
      arrives, `PermissionRequest` fires even under `defaultMode: auto`, `Stop` carries
      elapsed time. Both formerly-unverified items are now confirmed._
      **Incident 2026-08-16 (v0.1.1):** "sub agent done" repeated every ~32 s. Two
      causes: (1) an early test batch had run `set event.SubagentStop on` against the
      LIVE conf before the throwaway-config harness existed — test pollution, not a
      user setting; (2) a background subagent fired `SubagentStop` in a loop and nothing
      deduped it. Fixed by cleaning the conf, adding `repeat_cooldown` (default 60 s:
      identical line + same session inside the window speaks once), and saying
      "sub agent" (TTS read "subagent" as "soob-agent"). Tests: 45.
      Found+fixed during this: greedy `sed` in `jget` matched the LAST `"name":` in a
      session file — inside `formerNames` — so any `/rename`d session spoke its OLD
      name. Regression test added.
      Dropped the `userConfig` block from `plugin.json`: it made the CLI nag
      "1 userConfig option not yet set" on every install, which is exactly the friction
      we don't want. The script still honors `CLAUDE_PLUGIN_OPTION_PRESET` if set.
      Contributor note: `claude plugin update` is version-gated — for local iteration
      either bump `version` in both manifests or `uninstall` + `install`.
- [ ] **Windows without Git Bash**: hooks fall back to PowerShell there, and `sh`
      won't exist. Either ship a `bin/notify.ps1` twin selected by a `shell:
      powershell` hook set (must not double-fire where both shells exist) or document
      Git Bash as a requirement. Documented for now.
- [x] Publish: pushed, tagged `v0.1.0`; releases published for every version since.

## Tier 1 — Signal quality

- [x] **Say WHAT it needs permission for.** `PermissionRequest` hook (carries
      `tool_name` + `tool_input`) wired instead of the bare `permission_prompt`
      notification: "iriscale voice wants to run git push origin main" / "wants to
      use Edit". Bash commands truncated to 60 chars.
- [ ] **Speak a one-line summary of what was done.** `Stop` payload includes
      `transcript_path`; read the last assistant message and speak its first
      sentence: "done — tests pass, three files changed". Turns "something finished"
      into "is it worth switching back". Needs a JSONL last-line parse without jq —
      doable with `tail -n1` + sed for the `"text":"…"` field; watch length.
- [x] **Elapsed time** in the announcement ("done after 6 minutes") for turns ≥ 60 s.
      `say_elapsed=false` to turn off.
- [x] **Failure reason** spoken on `StopFailure` ("stopped: rate limit").

## Tier 2 — Attention management

- [ ] **Escalate if unattended**: re-announce a pending permission prompt after
      3 min, then 10. That's the one that actually blocks a session while you're
      heads-down.
- [ ] **Earcons** as an alternative to speech: a 200 ms tone per event type. Faster
      to parse, less intrusive on calls. `mode=earcon|speech|both`.
- [ ] **Persistent toast/notification** alongside speech (Windows toast, macOS
      Notification Center, Linux `notify-send`) so a missed announcement is still
      visible. Prototype exists for Windows.
- [ ] **Per-session voice/pitch signature** so you can tell which terminal by ear.
      Shipped in the PowerShell prototype (2 voices × 3 rates); macOS has many
      voices, so this gets better there.

## Tier 3 — Multi-session

- [x] **Status board** (shipped 0.1.11–0.1.16 as `sessions` / `board`; tray/menu-bar versions still open): a local page/tray showing every live session, its name,
      `busy|idle`, and time since last event. `~/.claude/sessions/*.json` already
      carries `pid`, `name`, `cwd`, `status`, `updatedAt`. Replaces polling five
      terminals.
- [ ] **Phone push** when away — Claude Code's Remote Control push
      (`agentPushNotifEnabled`) already covers part of this; document how they combine.

## Tier 4 — Beyond Claude Code (see docs/PLATFORMS.md for the full matrix)

Researched 2026-08-16. Six CLIs copied Claude Code's hook shape (JSON on stdin,
`session_id`/`cwd`/`Stop`/`PermissionRequest`), so one script + alias layers covers
them. Order below is by adapter effort × user base.

- [x] **alias layers in `iriscale-voice`** (0.1.6): payload from stdin *or* argv (Codex
      `notify`); field aliases (`sessionId`, `conversation_id`, `thread-id`,
      `workspace_roots[0]`…); event aliases (`agentStop`/`AfterAgent`/`TaskComplete`
      → Stop, `errorOccurred`/`stop{status=error}` → StopFailure,
      `permissionRequest`/`Notification{ToolPermission}` → PermissionRequest,
      `notification{agent_idle}` → idle_prompt). Synthetic-payload tests per agent.
- [~] **Codex CLI (shipped 0.1.6–0.1.10); Copilot CLI, Grok Build, Gemini CLI** install snippets
      (`docs/install/<agent>.md`) + `iriscale-voice install <agent>` that prints the
      snippet with the absolute path filled in. Copilot has the best three-state
      coverage (`agentStop` / `permissionRequest` / `errorOccurred`).
- [ ] **Junie CLI, Cursor, Devin CLI, OpenCode/Kilo CLI** (OpenCode needs a
      ~20-line TS plugin that shells out to the script).
- [ ] **Windsurf/Cascade, Cline, Aider** (done-only signals).
- [ ] Backlog: Amp (TS plugin), Kiro (payload undocumented).
- [-] Zed, Warp, Roo Code, Kilo extension — no shell hook exists; only built-in
      sound settings. Re-check when Zed's hooks proposal (#57890) lands.
- Constraint: Claude Code and Codex are installed on the maintainers' machine; every other
  other adapter is written to spec and verified by users' logs, not by us.

## Cut

- [-] **Skip announcing when the terminal is focused.** Cut 2026-08-14. Concurrent
      sessions are often tabs inside one host process (Windows Terminal, Windsurf,
      Devin), so every session shares an ancestor PID and focusing ANY window
      suppressed ALL of them. Missing a real alert is worse than a redundant one.
      Kept as an exact-PID-only option, off by default, for one-window-per-session
      setups.

## Known gaps / debts

- `Notification` matcher names (`permission_prompt`, `idle_prompt`,
  `agent_completed`) come from docs and were verified against the script, not yet
  observed live from Claude Code. Watch the log for a day; a matcher that never
  appears is the tell.
- Idle timeout before `idle_prompt` fires appears undocumented and not
  configurable.
- Turn-start stamp files and the activity log grow unbounded — clean on
  `SessionEnd`, roll log at 1 MB.
- Windows: only 2 built-in voices, so per-session signatures can collide.
