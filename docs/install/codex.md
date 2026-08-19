# Codex CLI

Verified against Codex CLI 0.147.0 on Windows. Git for Windows is the only prerequisite.

## Recommended: one-command Windows install

Run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/justbuild-it/iriscale_voice/main/install.ps1 | iex
```

The installer downloads Iriscale Voice to `%LOCALAPPDATA%\Programs\iriscale-voice`,
creates a stable launcher, adds it to your user `PATH`, registers PowerShell tab
completion, installs the `$iriscale-voice` Codex skill, and merges `notify` plus two
synchronous hooks into your Codex files. Existing files are backed up before changes
and unrelated settings and hooks remain.

Restart Codex and your terminal. In `/hooks`, confirm `UserPromptSubmit` and
`PermissionRequest` each show `Installed 1`, open each event, and trust its hook so
`Active` becomes `1`. Then verify:

```powershell
iriscale-voice status
iriscale-voice doctor codex
iriscale-voice test
```

Type `iriscale-voice ` and press Tab for shell commands. In Codex, invoke the bundled
`$iriscale-voice` skill for status, diagnostics, and configuration help. Codex owns
slash commands, so Claude Code's `/iriscale-voice:*` commands are not used here.

Lifecycle commands:

```powershell
iriscale-voice update
iriscale-voice uninstall codex
```

The rest of this page documents the generated configuration for manual or non-Windows
setups.

## Basic: one line, no trust prompts

Codex's `notify` setting runs a program when a turn completes and passes the turn's
JSON as the last argument. Add this **at the top** of `~/.codex/config.toml`
(`notify` is a top-level key — it must come before any `[table]` header):

```toml
# macOS / Linux
notify = ["/absolute/path/to/iriscale-voice", "notify"]

# Windows (Git Bash's sh.exe; adjust the checkout path)
notify = ["C:\Program Files\Git\bin\sh.exe", "C:/path/to/iriscale_voice/bin/iriscale-voice", "notify"]
```

Restart Codex. You'll hear *"<session> done"* after every turn — `<session>` is the
name you gave with Codex's `/rename` (read from `~/.codex/session_index.jsonl`), or
the folder name.

`iriscale-voice install codex` prints this snippet with your paths filled in.
`iriscale-voice install codex --apply` performs the Windows installation.

## Full (optional): permission prompts and elapsed time — two hooks

Codex hooks use the same JSON-on-stdin shape as Claude Code. Create
`~/.codex/hooks.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command",
        "command": "sh \"/absolute/path/to/iriscale-voice\" stamp",
        "commandWindows": "\"C:\Program Files\Git\bin\sh.exe\" \"C:/path/to/iriscale_voice/bin/iriscale-voice\" stamp",
        "timeout": 10 } ] }
    ],
    "PermissionRequest": [
      { "hooks": [ { "type": "command",
        "command": "sh \"/absolute/path/to/iriscale-voice\" PermissionRequest",
        "commandWindows": "\"C:\Program Files\Git\bin\sh.exe\" \"C:/path/to/iriscale_voice/bin/iriscale-voice\" PermissionRequest",
        "timeout": 30 } ] }
    ]
  }
}
```

Keep these hooks synchronous: Codex 0.147 skips definitions containing `"async": true`,
so they appear as `Installed 0` and cannot be trusted.

Restart Codex, run **`/hooks`**, and confirm both events show **Installed 1**. Only then
open each event and trust its hook; **Active** should become **1**. Codex stores a hash
in `config.toml`, so editing `hooks.json` prompts for trust again. This gives
*"<session> is waiting for your answer to run git status"* before you answer a yes/no,
and *"done after N minutes"* on long turns.

Run `iriscale-voice doctor codex` for a read-only check of `config.toml` and
`hooks.json`. It identifies missing definitions and the unsupported asynchronous form;
the final Installed/Active check remains visible in `/hooks`.

Why not more hooks? Every extra hook is another trust prompt. `Stop` is already
covered by `notify`; `SubagentStop`/`SessionEnd` are verbose-only. Two is the minimum
that adds real value.

## What Codex has and hasn't

| moment | Codex signal | you hear |
|---|---|---|
| turn done | `notify` `agent-turn-complete` (or hook `Stop`) | "<session> done" |
| needs approval | hook `PermissionRequest` (`tool_name`, `tool_input.command`) | "<session> is waiting for your answer to run …" |
| turn failed | — (Codex has no failure event) | — |
| idle, waiting for you | — (Codex has no idle notification) | — |

Same config file, presets and quiet hours as Claude Code — one setup for every agent.
Everything lands in `~/.claude/iriscale-voice.log`.
