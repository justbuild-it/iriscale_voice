# Platform support

Which coding agents iriscale_voice can announce for, how, and in what order we
plan to add them. Researched 2026-08-16 from each vendor's docs; each row links its
source. "Docs verified" means the config shape and event names were read from official
docs; "verified live" means the adapter has also been run end to end. Claude Code and
Codex CLI have been verified live.

## The good news: most CLIs copied Claude Code's hook shape

Codex CLI, Copilot CLI, Grok Build, Gemini CLI, Junie CLI and Devin CLI all run a
shell command per lifecycle event with **JSON on stdin**, and most use the same field
names (`session_id`, `cwd`, `hook_event_name`, `tool_name`, events `Stop` /
`PermissionRequest`). Grok and Devin will even read `~/.claude/settings.json`
directly. So `bin/iriscale-voice` is already ~90 % of an adapter for six agents; the work
is a field-alias layer, an event-alias layer, and per-agent install snippets.

## Matrix

| # | Agent | Mechanism | done | needs input | error | session + cwd | Adapter effort | Status |
|---|---|---|---|---|---|---|---|---|
| — | **Claude Code** | plugin hooks | `Stop` | `PermissionRequest`, `Notification:idle_prompt` | `StopFailure` | yes | — | **shipped** |
| 1 | **Codex CLI** (OpenAI) | [`notify` or optional hooks](install/codex.md) | `agent-turn-complete` / `Stop` | `PermissionRequest` | — | yes (`thread-id`/`session_id`, `cwd`, `/rename`) | done | **0.1.6 — verified live** |
| 2 | **Copilot CLI** (GitHub) | `~/.copilot/hooks/*.json`, `.github/hooks/*.json` | `agentStop`, `notification:agent_idle` | `permissionRequest`, `notification:permission_prompt` | `errorOccurred` | yes (`sessionId`, `cwd` — camelCase) | small: camelCase aliases + event map. Best three-state coverage of any non-Claude agent | 0.1.4–0.1.6 |
| 3 | **Grok Build** (xAI) | `~/.grok/hooks/*.json` (also reads `.claude/settings.json`) | `Stop` | `Notification` (subtypes unverified) | `StopFailure` | yes (`sessionId`, `cwd`) | tiny | 0.1.4–0.1.6 |
| 4 | **Gemini CLI** (Google) | `hooks` in `~/.gemini/settings.json` | `AfterAgent` | `Notification` w/ `notification_type: ToolPermission` | — | yes (`session_id`, `cwd`) | small: event map | 0.1.4–0.1.6 |
| 5 | **Junie CLI** (JetBrains) | `hooks` in `~/.junie/config.json` | `Stop` | `PermissionRequest` | `StopFailure` (`error`) | no session/cwd → falls back to "Claude"/folder unknown | small; name from `$PWD` | 0.1.9 |
| 6 | **Cursor** | `~/.cursor/hooks.json`, `.cursor/hooks.json` | `stop` w/ `status: completed` | — (only pre-hooks; no "user is being asked" event) | `stop` w/ `status: error` | partial: `conversation_id`, `workspace_roots[]`, no cwd | small: status→event, name from `workspace_roots[0]` | 0.1.9 |
| 7 | **Devin CLI** | `~/.config/devin/config.json`, `.devin/hooks.v1.json` (also reads `.claude/settings.json`) | `Stop` | `PermissionRequest` | — | partial: `session_id`, `DEVIN_PROJECT_DIR` env | tiny | 0.1.9 |
| 8 | **OpenCode / Kilo CLI** | JS/TS plugin in `~/.config/opencode/plugins/` | `session.idle` | `permission.asked` | `session.error` | yes | medium: a 20-line TS plugin that shells to `iriscale-voice` | 0.1.9 |
| 9 | **Windsurf / Cascade** | `~/.codeium/windsurf/hooks.json` | `post_cascade_response` | — | — | partial (`trajectory_id`) | small, done-only | 0.1.13 |
| 10 | **Cline** (VS Code) | executable in `~/Documents/Cline/Hooks/` | `TaskComplete` | — | `TaskCancel` (also on error) | partial (`taskId`, `workspaceRoots`) | small; Windows support unverified | 0.1.13 |
| 11 | **Aider** | `--notifications-command "cmd"` | yes (no payload) | — | — | no | trivial, done-only | 0.1.13 |
| 12 | **Amp** (Sourcegraph) | TS plugin `agent.end`; built-in bell only | `agent.end` | — | — | partial | medium | backlog |
| 13 | **Kiro CLI** | `.kiro/hooks/*.json` `Stop` | yes | — | — | undocumented | unknown | backlog |
| — | **Zed, Warp, Roo Code, Kilo (extension)** | no shell hook — built-in sound/notification settings only | | | | | not possible today | — |

## Design for multi-agent support (0.1.4)

Keep one script. Add three thin layers, all inside `bin/iriscale-voice`:

1. **Payload source** — stdin (everyone) **or** last argv (Codex `notify`).
2. **Field aliases** — `session_id | sessionId | conversation_id | thread-id | taskId`,
   `cwd | workspace_roots[0] | workspaceRoots[0] | DEVIN_PROJECT_DIR | $PWD`.
3. **Event aliases** — normalize onto the five we speak:
   `Stop ← agentStop | AfterAgent | TaskComplete | stop{status=completed} | agent-turn-complete | session.idle | post_cascade_response`
   `StopFailure ← errorOccurred | stop{status=error} | TaskCancel | session.error`
   `PermissionRequest ← permissionRequest | Notification{ToolPermission} | permission.asked`
   `idle_prompt ← notification{agent_idle}`.

Then `docs/install/<agent>.md` with the exact JSON to paste for each, and a
`iriscale-voice install <agent>` helper that prints (not writes) that snippet with the
absolute script path filled in. Writing into another tool's config file is left to the
user for now — those files are theirs.

Session naming outside Claude Code: Codex has `/rename`; its name is resolved from
`~/.codex/session_index.jsonl`. Other agents currently use the working-directory
folder, so name project folders well.

## What we can and cannot verify from here

Claude Code and Codex CLI are installed on the maintainer's machine and verified live.
Other adapters are written to documented payloads and covered by synthetic-payload
tests in `test/run.sh`; their first real-world confirmation will come from users.

Sources: [Codex hooks](https://learn.chatgpt.com/docs/hooks) · [Codex config](https://learn.chatgpt.com/docs/config-file/config-reference) · [Copilot hooks](https://docs.github.com/en/copilot/reference/hooks-reference) · [Grok hooks](https://docs.x.ai/build/features/hooks) · [Gemini hooks](https://geminicli.com/docs/hooks/reference/) · [Junie hooks](https://junie.jetbrains.com/docs/junie-cli-hooks.html) · [Cursor hooks](https://cursor.com/docs/agent/hooks) · [Devin hooks](https://docs.devin.ai/cli/extensibility/hooks/overview) · [OpenCode plugins](https://opencode.ai/docs/plugins/) · [Kilo plugins](https://kilo.ai/docs/automate/extending/plugins) · [Cascade hooks](https://docs.devin.ai/desktop/cascade/hooks) · [Cline hooks](https://docs.cline.bot/features/hooks/hook-reference) · [Aider options](https://aider.chat/docs/config/options.html) · [Amp manual](https://ampcode.com/manual) · [Kiro hooks](https://kiro.dev/docs/hooks/) · [Zed agent settings](https://zed.dev/docs/ai/agent-settings) · [Warp notifications](https://docs.warp.dev/agents/capabilities/agent-notifications/) · [Roo issue #12025](https://github.com/RooCodeInc/Roo-Code/issues/12025)
