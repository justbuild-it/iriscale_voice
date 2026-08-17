---
description: Set iriscale voice quiet hours, e.g. 22-8 (24h, may wrap midnight); 'off' clears
argument-hint: <start>-<end> | off
disable-model-invocation: true
allowed-tools: Bash(sh *)
---

If `$ARGUMENTS` is `off` (or empty), run:
`sh "${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice" config unset quiet_hours`
Otherwise run:
`sh "${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice" config set quiet_hours $ARGUMENTS`

Show the command's output verbatim. If it printed usage or an error, show that and stop — do not guess at settings. Never edit config files by hand; the CLI owns them.
