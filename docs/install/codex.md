# Codex CLI

Requires Codex CLI 0.154.0 or newer with `Stop` and `SessionEnd` lifecycle hooks.
Review all five hooks in `/hooks` after installation. Windows also needs Git for Windows.

## Recommended: one command, any OS

With Node 18+ (macOS, Linux, Windows):

```sh
npx @iriscale/voice@latest install codex --apply
```

It installs the script to a stable directory, puts `iriscale-voice` on your `PATH`,
installs the `$iriscale-voice` skill, and merges five lifecycle hooks into your Codex
files — backing up everything it edits. Full details, including what it writes and how
to undo it: [npm.md](npm.md). Node is not needed afterwards; Codex calls the shell
script directly.

## Windows without Node

Run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/justbuild-it/iriscale_voice/v0.1.31/install.ps1 | iex
```

The installer downloads Iriscale Voice to `%LOCALAPPDATA%\Programs\iriscale-voice`,
creates a stable launcher, adds it to your user `PATH`, registers PowerShell tab
completion, installs the `$iriscale-voice` Codex skill, and merges five
synchronous lifecycle hooks into your Codex files. Existing files are backed up before changes
and unrelated settings and hooks remain.

Restart Codex and your terminal. In `/hooks`, confirm `UserPromptSubmit`,
`PermissionRequest`, `PostToolUse`, `Stop`, and `SessionEnd` each show `Installed 1`, open each event, and trust its hook so
`Active` becomes `1`. Then verify:

```powershell
iriscale-voice status
iriscale-voice doctor codex
iriscale-voice test
```

Type `iriscale-voice ` and press Tab for shell commands. In Codex, invoke the bundled
`$iriscale-voice` skill for status, diagnostics, and configuration help. Codex owns
slash commands, so Claude Code's `/iriscale-voice:*` commands are not used here.

Lifecycle commands for **this** (PowerShell) install:

```powershell
iriscale-voice update
iriscale-voice uninstall codex
```

Installed with npm instead? Those verbs belong to npm — `npx @iriscale/voice@latest
update` / `npx @iriscale/voice@latest uninstall codex`. The command on your PATH tells
you which one you have, and names the exact line to run. See [npm.md](npm.md).

The rest of this page documents the generated configuration for manual setups.
`iriscale-voice install codex` (without `--apply`) prints it with your paths filled in.

When migrating a standalone PowerShell installation from v0.1.29, run the fresh
installer for the release containing this change. The old `update` command can
download new files while finishing with its already-loaded, old three-hook setup.
Do not rely on that command alone for this migration. For a reviewed development
checkout, run this from its repository directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -SourcePath . -SkipPath -SkipProfile
```

Then verify all five hooks and the absence of the old Voice notifier before
restarting Codex.

## Why lifecycle hooks are required

Codex's `PermissionRequest` runs before automatic review or the human approval UI.
Voice announces a permission wait only when the current turn's transcript records
`approvals_reviewer: "user"`. Automatic review and bypass mode stay quiet. If that
metadata cannot be verified, Voice also stays quiet instead of reporting a false wait.
It reads at most the final 256 KiB and caches the reviewer per session and turn at
prompt submit, so long transcripts do not slow every hook. Completion alerts still run.

On Windows, Codex runs hooks through the session's shell. Voice generates an
explicit PowerShell invocation that also works from cmd. The UTF-16 encoded
command preserves literal installation paths across both shells; it decodes to
the hook bridge path, Git Bash path, one fixed event argument, and exit-code propagation. Reapply
the installer and review the changed hooks if an older setup reports
`Unexpected token 'codex-stamp'` or `hook exited with code 1` on prompt submission.

The Windows hook bridge starts a hidden worker without inheriting Codex's output
pipes. This lets background reminders and speech continue after the foreground
hook exits. Hook input is staged in a unique temporary directory with an explicit
current-user-only Windows ACL, deleted before
the runtime starts, and the remaining result files are removed when the worker
finishes. Reapply installation and review changed hooks to receive this launcher
update; copying only the shell runtime is insufficient.

Legacy Codex `notify` also runs for temporary internal requests. Those requests
have no user-visible session name, so they produced misleading project-folder
announcements and extra board rows. Lifecycle hooks are disabled for those internal
requests. Voice now uses these five hooks:

| Hook | Purpose |
| --- | --- |
| UserPromptSubmit | Mark the user session working |
| PermissionRequest | Mark it as waiting for an answer |
| PostToolUse | Clear the waiting state after the approved tool finishes |
| Stop | Announce completion and mark the session ready |
| SessionEnd | Remove the ended session from the board |

Installers remove an old Iriscale Voice `notify` entry and restore any unrelated
notifier they previously displaced. Existing unrelated notifier settings remain.
The legacy Voice notification entry points ignore events from processes still
using cached old configuration. Reapply the installer and restart Codex to receive
completion through `Stop`; replacing only the runtime is insufficient.

Use `iriscale-voice install codex` to print the hook definitions for a manual
setup. Review and trust changed hooks in `/hooks`. Automatic trust is not enabled.

The board reads the latest matching title in `session_index.jsonl` on refresh.
A genuine unnamed user session falls back to its project folder. Two sessions in
the same folder remain distinct. Old rows created before this migration cannot
be identified safely by their folder name alone; forget only known stale rows.

`SessionEnd` removes rows when Codex reports the session ended. Abrupt termination
can skip that event, so a row is not proof of a currently open terminal. The
24-hour inactivity fallback remains for sessions without a PID. Approval alone
does not trigger `PostToolUse`: a long-running approved tool can remain marked as
waiting until its result arrives.

The standalone shell `doctor codex` performs basic checks; the npm doctor
structurally validates the installed command targets. Neither proves audible
output or a trusted live hook. Test those in Codex after restarting.
