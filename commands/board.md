---
description: Open the iriscale voice session board in its own terminal window (every live session, its state, click to raise)
disable-model-invocation: true
allowed-tools: Bash(sh *)
---

Run: `sh "${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice" board --open`

Show the command's output verbatim. If it says the board is already running, say so. To
keep the window open automatically, the user can run
`sh "${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice" config set board_autostart true` — offer
that only if they ask how to keep it open. Never edit config files by hand; the CLI owns
them.
