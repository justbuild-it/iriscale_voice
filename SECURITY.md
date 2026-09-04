# Security

## What this software does on your machine

- **Runs on every agent hook event** as your user, reading JSON from the agent and
  speaking text through your OS's speech engine. Nothing runs with elevated rights.
- **Writes** its config (`~/.claude/iriscale-voice.conf`), an activity log
  (`~/.claude/iriscale-voice.log`, rolled at 1 MB), one small state file per session
  (`~/.claude/iriscale-voice-sessions/`), and scratch files under
  `$TMPDIR/iriscale-voice/` (created mode 700).
- **Speaks and logs what the agent asked permission for** - up to 60 characters of the
  command, because that is what lets you decide from across the room. Words that look
  like credentials (`Bearer …`, `sk-…`, `ghp_…`, `AKIA…`, `password=…`, `user:pass@host`)
  are replaced with "redacted" before the text reaches the speaker or the log. The
  scrubber is pattern-based and cannot catch every secret shape; in a shared office or
  on calls set `command_detail=program` to speak only the program name, or
  `command_detail=full` if you explicitly want the verbatim command.
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
irm https://raw.githubusercontent.com/justbuild-it/iriscale_voice/v0.1.18/install.ps1 -OutFile install.ps1
# read it, then:
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Pin to a release tag rather than `main` if you want a fixed, reviewed version.

## Reporting a vulnerability

Email **security@iriscale.com** or open a GitHub security advisory on this repository.
Please do not file public issues for security problems. We aim to acknowledge within
3 business days and to ship a fix as a patch release.
