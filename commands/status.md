---
description: Show iriscale voice status: preset, what will speak, quiet hours, config path
disable-model-invocation: true
allowed-tools: Bash(sh *)
---

Run: `sh "${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice" status`

Show the command's output verbatim. If it printed usage or an error, show that and stop — do not guess at settings. Never edit config files by hand; the CLI owns them.
