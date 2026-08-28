# Design note: a lightweight visual session board

Status: **proposal** (2026-08-28). Feasibility: **high**. Not started.

## The ask

Alongside the voice, a tiny always-visible indicator showing every running agent
session and its state — working / ready for review / blocked on you / dead — plus what
was last said for each. Agent-independent: Claude Code, Codex, whatever comes next.

## Finding 1: the data already exists — a prototype rendered it in one frame

No new plumbing was needed to draw this on the maintainer's machine (9 live Claude
sessions, 2 Codex threads):

```
iriscale voice — sessions   12:17:41

      SESSION                        STATE    FOR     LAST SAID
  ○  marketing_kb                   idle     30m     marketing kb is waiting for you
  ●  geo.2                          READY    4m      geo.2 done after 2 minutes
  ●  iriscale_voice                 working  1m      iriscale voice is waiting for you
  ●  copy_update.1                  READY    9m      copy update.1 is waiting for you
  ◌  codex_setup                    codex            (no live status feed)
  ◌  codex_iriscale_voice           codex            (no live status feed)
```

Sources, all plain files, all readable with builtins:

| source | gives | live? |
|---|---|---|
| `~/.claude/sessions/<pid>.json` (written by Claude Code) | pid, `/rename` name, cwd, **`busy` / `idle`**, `statusUpdatedAt` | yes — Claude updates it on every status change |
| `~/.codex/session_index.jsonl` (written by Codex) | thread id, `/rename` name, updated_at | names only, **no status** |
| `~/.claude/iriscale-voice.log` (written by us) | every event we announced, per session, timestamped | yes, but event-shaped, not state-shaped |

The gap is Codex (and every future agent): no status file. But every agent already
calls `bin/iriscale-voice` on its events — that script *is* the agent-agnostic funnel.

## Finding 2: the missing piece is ~40 lines in the script we already have

Add a **state layer**: on every event, the script writes one small file per session,
`~/.claude/iriscale-voice/state/<session-id>` (or `$STATE`), containing:

```
agent=codex            # claude | codex | copilot | ... (inferred from payload shape)
name=payments_api
status=blocked         # working | ready | blocked | waiting | error | ended
since=1756400000       # epoch of this status
said=payments api is waiting for your answer to run git push
```

Transitions come for free from events we already handle:

| event | status |
|---|---|
| `stamp` (UserPromptSubmit) | working |
| `Stop` / `agent-turn-complete` | **ready** |
| `PermissionRequest` | **blocked** (needs an answer — the one that stops progress) |
| `idle_prompt` | waiting |
| `StopFailure` | **error** |
| `SessionEnd` | ended → file removed |

That state layer is what makes the board **independent of the agent**: any tool that
can run a command on its lifecycle events feeds it. It also fixes the Codex gap
without asking Codex for anything. Cost: builtins only (a `printf` to a file), so the
spawn guard stays at ≤1 and hook latency is unchanged.

Liveness: `~/.claude/sessions` files can outlive their process; the board checks the
pid (`kill -0` / `tasklist`) and greys or drops dead ones. For agents with no pid on
disk, a state file untouched for N hours is shown as stale.

## Finding 3: the viewer format — measured, not guessed

| format | how | memory (measured here) | cross-platform | always visible? |
|---|---|---|---|---|
| **Terminal pane** (`iriscale-voice board`) | POSIX `sh` loop, ANSI colours, re-reads state files every 1–2 s | ~5 MB (a `sh`) | yes, one implementation | only if you give it a split |
| **Windows tray / topmost mini-window** | PowerShell + WinForms, zero installs | **91 MB** | Windows only | yes |
| **Tiny native window** | Rust/C Win32, or AutoHotkey | 3–10 MB | per-OS builds, a compiler in the loop | yes |
| **macOS menu bar** | xbar / SwiftBar plugin = a shell script that prints lines like `● billing done \| color=green` | host app ~40 MB, shared with other plugins | macOS only | yes |
| **Linux bar** | Waybar / Polybar custom module = a script that prints one line | ~0 (bar already running) | Linux only | yes |
| **Toast / notification centre** | already on the roadmap | 0 | per-OS | no — ephemeral |
| **Terminal tab titles** | ideal in theory | 0 | — | **not feasible**: hooks run in a child process with no handle to the session's terminal; Claude Code owns its tab title |
| **Web page / Electron** | local HTML | 150 MB+ or needs a server (breaks zero-dependency) | yes | no |

The honest conclusion: **"incredibly lightweight" and "always visible" pull in
opposite directions on Windows**, where the only zero-install always-on-top option is
PowerShell at ~90 MB. Everywhere else there's a native bar that takes a one-line script.

## Recommendation: state layer in core, thin viewers on top

Ship in this order, each its own patch release:

1. **State layer** (`0.1.x`) — the ~40 lines above, plus `iriscale-voice sessions`
   printing the board once as plain text. Zero new dependencies; every agent benefits;
   makes everything below possible. Highest value per line.
2. **`iriscale-voice board`** — the terminal pane, refreshing in place. Cross-platform
   from one `sh` file; ~5 MB; drop it in a narrow split of Windows Terminal / tmux /
   iTerm. This is the "small little widget that runs alongside the sessions" for people
   who live in a terminal, and it's the one we can fully test here.
3. **macOS menu bar + Linux bar plugins** — each is a 20-line script that reads the
   state dir and prints lines in the bar's format. Untestable on this machine; ship as
   "written to spec", let users confirm.
4. **Windows tray icon** — accept the PowerShell cost *as an opt-in* (`iriscale-voice
   board --tray`), because the alternative is a compiled binary and a build pipeline.
   Colour = worst state across sessions (red blocked > yellow ready > green working);
   hover = the list; click = the terminal board. Revisit a native build only if demand
   shows up.

What the board deliberately won't do: **focus a session on click**. All sessions
usually live as tabs in one host process (Windows Terminal, Devin, Windsurf), so the OS
can only raise the host window, not the tab — the same limitation that killed
focus-based suppression on day one. It can show you *which* session; you switch.

## Effort

| step | size | risk |
|---|---|---|
| state layer + `sessions` | small (≈60 lines + tests) | low — builtins, same guards |
| `board` pane | small (≈100 lines) | low |
| macOS/Linux bar scripts | small each | medium — unverified platforms |
| Windows tray | medium (≈150 lines PowerShell) | low, but 90 MB |

## Open questions

- Should the state directory live under `~/.claude/` (where our config and log already
  are) or somewhere agent-neutral like `~/.iriscale-voice/`? Leaning neutral, since the
  point is that it isn't Claude-specific — but that's a config-path change and needs a
  migration note.
- Colour semantics: is a session that finished 40 minutes ago still "ready", or has it
  become "idle"? The prototype used 15 minutes; probably a setting.
