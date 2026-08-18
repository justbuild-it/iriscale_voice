# Codex CLI

Verified against Codex CLI 0.147.0 on Windows (Git Bash). Two tiers — most people
only need the first.

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
        "async": true, "timeout": 10 } ] }
    ],
    "PermissionRequest": [
      { "hooks": [ { "type": "command",
        "command": "sh \"/absolute/path/to/iriscale-voice\" PermissionRequest",
        "commandWindows": "\"C:\Program Files\Git\bin\sh.exe\" \"C:/path/to/iriscale_voice/bin/iriscale-voice\" PermissionRequest",
        "async": true, "timeout": 30 } ] }
    ]
  }
}
```

Then in Codex run **`/hooks`** and press **`t`** on each of the two — Codex requires a
human to trust every hook definition once (it stores a hash in `config.toml`; editing
`hooks.json` re-prompts). That gives *"<session> wants to run git status"* before you
answer a yes/no, and *"done after N minutes"* on long turns.

Why not more hooks? Every extra hook is another trust prompt. `Stop` is already
covered by `notify`; `SubagentStop`/`SessionEnd` are verbose-only. Two is the minimum
that adds real value.

## What Codex has and hasn't

| moment | Codex signal | you hear |
|---|---|---|
| turn done | `notify` `agent-turn-complete` (or hook `Stop`) | "<session> done" |
| needs approval | hook `PermissionRequest` (`tool_name`, `tool_input.command`) | "<session> wants to run …" |
| turn failed | — (Codex has no failure event) | — |
| idle, waiting for you | — (Codex has no idle notification) | — |

Same config file, presets and quiet hours as Claude Code — one setup for every agent.
Everything lands in `~/.claude/iriscale-voice.log`.
