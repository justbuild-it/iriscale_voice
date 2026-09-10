---
description: Choose which voice speaks - no argument shows the voices worth using, a name sets it and speaks a sample, default restores the system voice
argument-hint: [<voice name> | default | --all]
disable-model-invocation: true
allowed-tools: Bash(sh *)
---

Run: `sh "${CLAUDE_PLUGIN_ROOT}/bin/iriscale-voice" speaker $ARGUMENTS`

The output is column-aligned terminal text. Pasted into a chat pane it does not wrap, so it
scrolls sideways and the ends of lines are lost. Read it and answer in your own words
instead of quoting the block:

- **It listed voices** — name the voice that is set now, then give the voices as a compact
  markdown table of name and locale, exactly the names it printed. Never invent, rename,
  drop or add one.
- **It set a voice** — one line: which voice is set now, and that it spoke a sample.
- **Usage, an error, or anything unexpected** — show that text as it is and stop. Do not
  guess at settings, and never suggest a voice the command did not list.

After a listing, close with the command to run, written out, not described — a name from
the table you just showed, in quotes:

```
/iriscale-voice:speaker "Samantha"
```

Say that it sets the voice and speaks a sample straight away, that a name containing spaces
or parentheses must keep its quotes, and that `/iriscale-voice:speaker default` goes back to
the system voice. Add `/iriscale-voice:speaker --all` only if the output offered it.

Never edit config files by hand; the CLI owns them.
