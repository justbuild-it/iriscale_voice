---
description: Set how long after a turn ends a keypress in that session still marks it reviewed (sets Claude Code's idle window; 10 minutes recommended)
disable-model-invocation: true
allowed-tools: Bash(sh *)
---

Run: `sh "${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice" review-window $ARGUMENTS`

Show the command's output verbatim. If it printed usage or an error, show that and stop — do not guess at settings. Never edit config files by hand; the CLI owns them. If the output says to restart Claude Code, tell the user so in one line.
