---
description: Set the iriscale voice preset: basic, standard, verbose, or off
argument-hint: basic | standard | verbose | off
disable-model-invocation: true
allowed-tools: Bash(sh *)
---

Run: `sh "${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice" config set preset $ARGUMENTS`

Show the command's output verbatim. If it printed usage or an error, show that and stop — do not guess at settings. Never edit config files by hand; the CLI owns them.
