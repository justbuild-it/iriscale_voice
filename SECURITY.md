# Security

## What this software does on your machine

- **Runs on every agent hook event** as your user, reading JSON from the agent and
  speaking text through your OS's speech engine. Nothing runs with elevated rights.
- **Writes** its config (`~/.claude/iriscale-voice.conf`), an activity log
  (`~/.claude/iriscale-voice.log`, rolled at 1 MB), one small state file per session
  (`~/.claude/iriscale-voice-sessions/`), and scratch files under
  `$TMPDIR/iriscale-voice/` (created mode 700).
- **Speaks and logs what the agent asked permission for.** By default only the program
  and its first word ("git push", "npm test"). `speak_full_command=true` speaks up to
  60 characters with token-like words redacted - but treat that as opt-in exposure.
- **The Windows installer** (`install.ps1`) edits your user PATH, your PowerShell
  `$PROFILE`, and Codex's `~/.codex/config.toml` / `hooks.json`, taking a backup of
  each file before writing. `iriscale-voice uninstall codex` reverses exactly those
  edits. It never asks for elevation.
- **Session names and ids from the agent are untrusted.** Names are scrubbed before
  they reach a shell or the speech engine; ids are restricted to `[A-Za-z0-9._-]`
  before they become file names.

## Installing safely

The README's one-liner pipes a script from this repository into PowerShell. If you
prefer to inspect first:

```powershell
irm https://raw.githubusercontent.com/justbuild-it/iriscale_voice/v0.1.17/install.ps1 -OutFile install.ps1
# read it, then:
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Pin to a release tag rather than `main` if you want a fixed, reviewed version.

## Reporting a vulnerability

Email **security@iriscale.com** or open a GitHub security advisory on this repository.
Please do not file public issues for security problems. We aim to acknowledge within
3 business days and to ship a fix as a patch release.
