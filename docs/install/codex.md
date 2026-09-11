# Codex CLI

Completion and approval alerts were verified against Codex CLI 0.147.0 on Windows.
The resume hook requires a Codex version exposing `PostToolUse` in `/hooks`; confirm
installation and trust after updating. Windows also needs Git for Windows.

## Recommended: one command, any OS

With Node 18+ (macOS, Linux, Windows):

```sh
npx @iriscale/voice@latest install codex --apply
```

It installs the script to a stable directory, puts `iriscale-voice` on your `PATH`,
installs the `$iriscale-voice` skill, and merges `notify` plus three hooks into your Codex
files — backing up everything it edits. Full details, including what it writes and how
to undo it: [npm.md](npm.md). Node is not needed afterwards; Codex calls the shell
script directly.

## Windows without Node

Run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/justbuild-it/iriscale_voice/v0.1.29/install.ps1 | iex
```

The installer downloads Iriscale Voice to `%LOCALAPPDATA%\Programs\iriscale-voice`,
creates a stable launcher, adds it to your user `PATH`, registers PowerShell tab
completion, installs the `$iriscale-voice` Codex skill, and merges `notify` plus three
synchronous hooks into your Codex files. Existing files are backed up before changes
and unrelated settings and hooks remain.

Restart Codex and your terminal. In `/hooks`, confirm `UserPromptSubmit`,
`PermissionRequest`, and `PostToolUse` each show `Installed 1`, open each event, and trust its hook so
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

## Basic: one line, no trust prompts

Codex's `notify` setting runs a program when a turn completes and passes the turn's
JSON as the last argument. Add this **at the top** of `~/.codex/config.toml`
(`notify` is a top-level key — it must come before any `[table]` header):

```toml
# macOS / Linux
notify = ["/absolute/path/to/iriscale-voice", "notify"]

# Windows (keep the PowerShell bridge beside the shell script)
notify = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", "C:/path/to/iriscale_voice/bin/iriscale-voice-notify.ps1", "C:/Program Files/Git/bin/bash.exe"]
```

Restart Codex. You'll hear *"<session> done"* after every turn — `<session>` is the
name you gave with Codex's `/rename` (read from `~/.codex/session_index.jsonl`), or
the folder name.

The Windows bridge passes JSON to Git Bash through stdin, preserving backslashes
in project paths. Both installers configure it automatically. After upgrading,
reapply the Codex installation and restart Codex so the new command takes effect.
Replacing only the shell script leaves the old notification command in place.

The board reads the latest matching title in `session_index.jsonl` on each refresh,
so `/rename` changes appear without another completed turn. If Codex has no title
record for a session, the project folder is the fallback. Previously damaged
unnamed rows are corrected by their next notification. Titles stored only by a
different Codex home or application are not available to this lookup.

`iriscale-voice install codex` prints this snippet with your paths filled in.
`iriscale-voice install codex --apply` performs the Windows installation.

## Full (optional): permission prompts, elapsed time, and resume — three hooks

Codex hooks use the same JSON-on-stdin shape as Claude Code. Create
`~/.codex/hooks.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command",
        "command": "sh \"/absolute/path/to/iriscale-voice\" codex-stamp",
        "commandWindows": "\"C:/Program Files/Git/bin/sh.exe\" \"C:/path/to/iriscale_voice/bin/iriscale-voice\" codex-stamp",
        "timeout": 10 } ] }
    ],
    "PermissionRequest": [
      { "hooks": [ { "type": "command",
        "command": "sh \"/absolute/path/to/iriscale-voice\" codex-PermissionRequest",
        "commandWindows": "\"C:/Program Files/Git/bin/sh.exe\" \"C:/path/to/iriscale_voice/bin/iriscale-voice\" codex-PermissionRequest",
        "timeout": 30 } ] }
    ],
    "PostToolUse": [
      { "hooks": [ { "type": "command",
        "command": "sh \"/absolute/path/to/iriscale-voice\" codex-resume",
        "commandWindows": "\"C:/Program Files/Git/bin/sh.exe\" \"C:/path/to/iriscale_voice/bin/iriscale-voice\" codex-resume",
        "timeout": 10 } ] }
    ]
  }
}
```

These handlers return promptly and keep their definitions synchronous for compatibility.
Current Codex supports asynchronous hooks too; unrelated asynchronous hooks can coexist.

Restart Codex, run **`/hooks`**, and confirm all three events show **Installed 1**. Only then
open each event and trust its hook; **Active** should become **1**. Codex stores a hash
in `config.toml`, so editing `hooks.json` prompts for trust again. This gives
*"<session> is waiting for your answer to run git status"* before you answer a yes/no,
and *"done after N minutes"* on long turns.

Run `iriscale-voice doctor codex` for a read-only check of `config.toml` and
`hooks.json`. The shell command performs basic file checks; use
`npx @iriscale/voice@latest doctor codex` for structural and target validation.
The final Installed/Active check remains visible in `/hooks`.

Why not more hooks? Every extra hook is another trust prompt. `Stop` is already
covered by `notify`. The third hook cancels stale permission reminders after the
approved tool finishes. An approval click does not itself fire this hook, so a
long-running tool can remain marked as waiting until its result arrives.

## What Codex has and hasn't

| moment | Codex signal | you hear |
|---|---|---|
| turn done | `notify` `agent-turn-complete` (or hook `Stop`) | "<session> done" |
| needs approval | hook `PermissionRequest` (`tool_name`, `tool_input.command`) | "<session> is waiting for your answer to run …" |
| approved tool finished | `PostToolUse` | silent; clears the blocked state |
| turn failed | not wired by this integration | — |
| idle, waiting for you | not wired by this integration | — |

Same config file, presets and quiet hours as Claude Code — one setup for every agent.
Everything lands in `~/.claude/iriscale-voice.log`.

Contracts: [Codex hooks](https://learn.chatgpt.com/docs/hooks) and
[completion notify](https://learn.chatgpt.com/docs/config-file/config-advanced).
