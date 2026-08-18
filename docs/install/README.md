# Installing for other agents

Claude Code users: `/plugin marketplace add justbuild-it/iriscale_voice` and
`/plugin install iriscale-voice@iriscale` — nothing else needed.

Every other agent calls the same script, `bin/iriscale-voice`, from its own hook or
notify setting. One page per agent, each with the exact snippet to paste:

- [Codex CLI](codex.md) — verified live
- Copilot CLI, Grok Build, Gemini CLI — next (see [../PLATFORMS.md](../PLATFORMS.md))

`iriscale-voice install <agent>` prints the snippet for your machine with paths filled
in. It never writes to another tool's config — those files are yours.
