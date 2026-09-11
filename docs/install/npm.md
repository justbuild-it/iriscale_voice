# npm / npx — every agent, on macOS, Linux and Windows

One command per agent, on any OS that has Node 18+:

```sh
npx @iriscale/voice@latest install codex --apply     # Codex CLI
npx @iriscale/voice@latest install claude --apply    # Claude Code, without the plugin
```

The package is **`@iriscale/voice`**; the command it puts on your PATH is
**`iriscale-voice`**. npm resolves the one to the other because the package ships a
single executable — every example below keeps that distinction.

For Claude Code the [plugin](../../README.md#claude-code-any-os) is still the better
route — it updates itself and edits none of your files. Use the npx route when you want
one install path for every agent, or cannot reach the marketplace. **Do not run both**:
each event would fire twice and speak twice. The installer detects an installed plugin
and refuses (`--force` overrides).

Restart Codex and your terminal. In `/hooks`, confirm `UserPromptSubmit` and
`PermissionRequest` each show `Installed 1`, open each one and trust it so `Active`
becomes `1`. **Codex now speaks** — the hooks hold absolute paths, so none of this
depends on your `PATH`.

Running the CLI yourself (`status`, `doctor`, `board`, `test`) does need it on PATH.
`npx` links it into `~/.local/bin`, which macOS and many Linux distros do not put on
`PATH` by default; the installer prints the exact line for your shell, e.g.

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh
iriscale-voice doctor codex
```

Or skip the PATH edit entirely — a global install puts the command there for you:

```sh
npm install -g @iriscale/voice
iriscale-voice install codex --apply
```

> **Node is an install-time dependency only.** Nothing on the hook path goes through
> node: Codex calls `bin/iriscale-voice` — the same zero-dependency POSIX shell script
> — directly. Uninstall node afterwards and the voice keeps working.

## What `--apply` writes

Nothing runs on `npm install`; the installer only touches your files when you ask it to
with `--apply`. Every file it edits is copied to `<file>.iriscale-backup-<timestamp>`
first, and it rewrites only its own lines — your model, theme, and other hooks stay.

| what | where |
|---|---|
| the script | `~/.local/share/iriscale-voice/bin/iriscale-voice` (macOS/Linux, honours `XDG_DATA_HOME`) · `%LOCALAPPDATA%\Programs\iriscale-voice\bin\` (Windows, plus a `.cmd` launcher over Git Bash) |
| `notify` | first line of `~/.codex/config.toml` — it is a top-level key, so it must precede any `[table]`. Codex allows only one, so a `notify` of your own is displaced and **given back on uninstall** |
| three hooks | `UserPromptSubmit`, `PermissionRequest`, and `PostToolUse` in `~/.codex/hooks.json` |
| the skill | `~/.codex/skills/iriscale-voice/` — invoke it in Codex as `$iriscale-voice` |
| PATH | a symlink in `~/.local/bin`, or the install dir added to your Windows user PATH — **skipped entirely** if `iriscale-voice` already resolves durably (as it does after `npm install -g`; npx's own temporary shim does not count) |

The script is installed to that stable directory rather than being run out of
`node_modules`, because hooks store an absolute path: an `npx` cache is temporary, and a
global install under `nvm` moves every time you switch Node versions.

`CODEX_HOME` and `IRISCALE_VOICE_INSTALL_ROOT` override the two roots.
`--skip-path` leaves PATH alone.

## Do it by hand instead

Without `--apply`, the installer writes nothing — it prints the exact configuration it
*would* write, with your machine's paths already filled in:

```sh
npx @iriscale/voice@latest install codex
```

## Update

The hooks execute the copy in the stable directory, not `node_modules`, so
`npm install -g @iriscale/voice@latest` on its own upgrades the CLI and leaves the voice
on the old version. `update` does both — and `doctor` and `status` tell you when they
have drifted apart (`STALE  your hooks run 0.1.23, but this package is 0.1.24`).

```sh
npx @iriscale/voice@latest update    # applies this latest package to recorded agent homes
iriscale-voice update               # from a global install: upgrades npm, then reapplies
```

Updating preserves the original PATH choice and recorded agent homes. Restart the
agents and close/reopen the session board afterwards; an already running board keeps
the code it started with. With the runtime-directory hardening update, old temporary
turn clocks and cooldowns are deliberately not imported from shared temporary storage.

`npx @iriscale/voice@latest doctor codex` validates the configured targets and hook
structure. The shell-only `doctor codex` performs basic file checks and directs you
to this deeper check; neither can confirm hook trust or that you heard the audio.

## Which `iriscale-voice` am I running?

The command the installer puts on your PATH is the **shell script** — it deliberately
knows nothing about node, so your hooks never depend on node being present. It handles
everything about running the tool (`status`, `board`, `sessions`, `test`, `config`), and
hands the four installer verbs back to npm, naming the exact command:

```
$ iriscale-voice uninstall codex
this copy was installed by the npm package, which owns 'uninstall codex'.
run:  npx @iriscale/voice@latest uninstall codex
      (already installed globally? npm exec -- @iriscale/voice uninstall codex)
```

`npm install -g @iriscale/voice` puts the node CLI on your PATH instead, and then every
command — installer verbs included — works directly.

## Uninstall

```sh
npx @iriscale/voice@latest uninstall codex    # or: uninstall claude
npm uninstall -g @iriscale/voice              # if you installed it globally
```

That removes the config it wrote, the skill, the commands, the PATH entry and the
install directory — restoring a `notify` of your own if ours displaced it. With both
agents installed, the shared script goes with the last one out.

Unrelated settings and hooks are left exactly as they were. Files the installer had to
create — `config.toml`, `hooks.json`, `~/.codex` itself on a machine that had never run
Codex — are removed again if nothing else ended up in them, so a try-then-undo leaves no
trace. A file that was already yours is kept, minus our line, with a backup beside it.

## What `install claude --apply` writes

| what | where |
|---|---|
| the script | the same stable directory as the Codex install — both agents share one copy |
| eight hooks | `~/.claude/settings.json` under `hooks`, **appended** to whatever is already there — your own `Stop` or `Notification` hooks are untouched, and re-running replaces only our own entries |
| the skill | `~/.claude/skills/iriscale-voice/` |
| the commands | `~/.claude/commands/iriscale-voice-*.md` — spelled **`/iriscale-voice-status`**, `/iriscale-voice-preset` … (a hyphen, not the plugin's colon: `~/.claude/commands/` takes flat files only, and a subdirectory there is not a namespace — only skills namespace by directory) |

`${CLAUDE_PLUGIN_ROOT}`, which only exists inside the plugin system, is resolved to the
stable path in every hook and command as they are written. `CLAUDE_CONFIG_DIR` overrides
the target directory.

Check it afterwards with `iriscale-voice doctor claude` — it reports the hooks, skill and
commands it finds, and warns if the plugin is installed too (which would speak twice).

Uninstall with `iriscale-voice uninstall claude`. Installing both agents shares one copy
of the script: uninstalling one leaves the install directory in place for the other, and
the last one out removes it.

## The plugin, for comparison

```
/plugin marketplace add justbuild-it/iriscale_voice
/plugin install iriscale-voice@iriscale
```

Two lines, self-updating, and it edits none of your files — the better choice for Claude
Code unless you specifically want the npx route. It also keeps the nicer command spelling,
`/iriscale-voice:status`.
