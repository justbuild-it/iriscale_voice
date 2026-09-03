---
description: iriscale voice settings - list | get <key> | set <key> <value> | unset <key> | path
argument-hint: list | get <key> | set <key> <value> | unset <key> | path
disable-model-invocation: true
allowed-tools: Bash(sh *)
---

Run: `sh "${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice" config $ARGUMENTS`

If `$ARGUMENTS` is empty, run `config list`.

Show the command's output verbatim. If it printed usage or an error, show that and stop — do not guess at settings. Never edit config files by hand; the CLI owns them.
