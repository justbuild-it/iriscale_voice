---
description: iriscale voice settings: list 
argument-hint: list | get <key> | set <key> <value> | unset <key> | path
disable-model-invocation: true
allowed-tools: Bash(sh *)
---

Run: `sh "${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice"  get <key> | set <key> <value> | unset <key> | path|config $ARGUMENTS`

Show the command's output verbatim. If it printed usage or an error, show that and stop — do not guess at settings. Never edit config files by hand; the CLI owns them.
