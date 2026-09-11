# Security

## What this software does on your machine

- **Runs on every agent hook event** as your user, reading JSON from the agent and
  speaking text through your OS's speech engine. Nothing runs with elevated rights.
- **Writes** its config (`~/.claude/iriscale-voice.conf`), an activity log
  (`~/.claude/iriscale-voice.log`, rolled at 1 MB), one small state file per session
  (`~/.claude/iriscale-voice-sessions/`), and scratch files under
  `~/.claude/iriscale-voice-runtime/` (mode 700; symlinks and other owners rejected).
  `CLAUDE_CONFIG_DIR` relocates these files. Shared temporary directories are not reused.
- **Speaks and logs what the agent asked permission for** - up to 60 characters of the
  command, because that is what lets you decide from across the room. Words that look
  like credentials (`Bearer …`, `sk-…`, `ghp_…`, `AKIA…`, `password=…`, `user:pass@host`)
  are replaced with "redacted" before the text reaches the speaker or the log. The
  scrubber is pattern-based and cannot catch every secret shape; in a shared office or
  on calls set `command_detail=program` to speak only the program name, or
  `command_detail=full` if you explicitly want the verbatim command.
- **The installers** write a copy of the script to a fixed directory
  (`~/.local/share/iriscale-voice`, or `%LOCALAPPDATA%\Programs\iriscale-voice`), put that
  on your PATH, and edit the configuration of the agent you named:
  - `install codex` — `~/.codex/config.toml` (the single top-level `notify`),
    `~/.codex/hooks.json` (three events), `~/.codex/skills/iriscale-voice/`.
  - `install claude` — `~/.claude/settings.json` (eight hook events, **appended** to
    whatever is already there), `~/.claude/skills/iriscale-voice/`, and
    `~/.claude/commands/iriscale-voice-*.md`.
  - The Windows `install.ps1` additionally edits your PowerShell `$PROFILE`.

  Every file is backed up beside itself before it is written, your own entries are left
  in place, and `iriscale-voice uninstall <codex|claude>` reverses exactly those edits —
  including restoring a `notify` of your own that ours had to displace. Nothing asks for
  elevation. **Nothing is written until you ask**: `npm install` runs no install script,
  and `install <agent>` without `--apply` only prints what it would write.
- **Session names and ids from the agent are untrusted.** Names are scrubbed before
  they reach a shell or the speech engine; ids are restricted to `[A-Za-z0-9._-]`
  before they become file names.

## Installing safely

The README's one-liner pipes a script from this repository into PowerShell. If you
prefer to inspect first:

```powershell
irm https://raw.githubusercontent.com/justbuild-it/iriscale_voice/v0.1.28/install.ps1 -OutFile install.ps1
# read it, then:
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Pin to a release tag rather than `main` if you want a fixed, reviewed version.

The npm installer can be read the same way before it runs. Unpack the published
tarball, read `package/npm/`, and pin to that exact version when you install — replace
`X.Y.Z` with the release you reviewed:

```sh
npm pack @iriscale/voice@X.Y.Z && tar -xzf iriscale-voice-X.Y.Z.tgz   # read package/npm/
npx @iriscale/voice@X.Y.Z install codex           # prints its plan, writes nothing
npx @iriscale/voice@X.Y.Z install codex --apply
```

`npm view @iriscale/voice versions` lists what has been published.

## Reporting a vulnerability

Email **security@iriscale.com** or open a GitHub security advisory on this repository.
Please do not file public issues for security problems. We aim to acknowledge within
3 business days and to ship a fix as a patch release.
