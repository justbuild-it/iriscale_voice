# Repository audit — 2026-09-10

## Remediation — 2026-09-11

The `fix/audit-reliability` PR addresses the findings below under `[Unreleased]`.
The original audit is retained as evidence about 0.1.28; its line references describe
that reviewed revision, not the corrected source.

| Findings | Change | Regression coverage |
|---|---|---|
| R1 | Quoted credentials and API-key header values scrubbed; program mode skips environment assignments | `test/audit-runtime.sh`, existing privacy suite |
| R2 | Same-state updates retain reminder deadlines; resume cancels them | `test/audit-runtime.sh`, existing lifecycle suite |
| R3 | Private runtime directory under `CLAUDE_CONFIG_DIR`, owner/symlink checks, restrictive modes | `test/audit-runtime.sh` (Unix symlink case runs in Linux/macOS CI) |
| R4–R5 | AppleScript argv quoting, absolute paths, launch/speech failure reporting | `test/audit-runtime.sh` (stubbed native commands) |
| S1, S3 | TOML-aware boundaries, Unicode-escaped/case-sensitive keys, preflight and restore | Shared npm/PowerShell `test/audit-installer.js` fixtures |
| S2 | Individual owned handlers removed; Unicode sibling hooks preserved | Shared installer fixtures plus Claude mixed-group test |
| S4 | Latest npx package reapplies recorded homes and preserves PATH choice | Installer update fixture |
| S5 | Codex PostToolUse resume hook, structural npm doctor, honest approval timing | Installer/doctor fixtures and existing resume tests |
| S6 | Relative launcher path preserves Unicode installation directories | PowerShell Unicode fixture |

Native Mac audio/Terminal verification, a live Codex approval cycle, and publication
of the resulting npm release remain external verification/release tasks, tracked in
[issue #36](https://github.com/justbuild-it/iriscale_voice/issues/36), assigned to Puneet.

## Original audit

Reviewed local version 0.1.28 at `6d1f851ab54d474d79c462bfdd627de8b74139e7`.
`git ls-remote` confirmed that the [public repository](https://github.com/justbuild-it/iriscale_voice) had the same HEAD/main commit. This is a whole-repository review against the README, SECURITY.md, installation guides, and CONTRIBUTING.md, not a change-only review.

**Recommendation: ship a focused reliability and safety release before expanding the feature set.** The small dependency surface, local speech, stable runtime location, and cross-platform test matrix are useful foundations. There are nevertheless concrete credential-disclosure, configuration-preservation, and notification-lifecycle bugs.

## Validation and limits

- Windows/Git Bash runtime suite: **361 passed, 0 failed**. One `echo: write error: Permission denied` diagnostic was emitted despite the passing result; do not interpret the run as completely warning-free.
- Windows/Git Bash npm installer suite: **154 passed, 0 failed**.
- Initial attempts had shell PATH and sandbox filesystem failures; the results above are from subsequent runs with Git Bash utilities available and execution approved outside the sandbox.
- Additional isolated reproductions confirmed TOML setting loss, credential leaks, reminder loss, and false macOS diagnostic success. These are outside the existing suite's coverage.
- No native macOS audio/Terminal test or live Codex approval cycle was performed. macOS findings distinguish shell/control-flow evidence from native platform testing.
- Public main was verified; the published npm tarball, every release tag, GitHub account controls, and external dependency vulnerability databases were not comprehensively audited. The package declares no npm runtime dependencies, but still relies on the OS, shell, agent, and installer tooling.
- No implementation or user configuration was changed. This document is the only repository addition.

P1 means fix before the next promoted release; P2 means a material reliability or safety issue to address soon. Static findings are identified explicitly.

## Standards and runtime safety

### R1 — P1: default redaction leaks familiar credential forms

Location: [bin/iriscale-voice:1764](../../bin/iriscale-voice#L1764).

With default `command_detail=redacted`, an isolated permission payload containing:

```text
curl -H "x-api-key: supersecret123" https://x
```

produces text containing `x-api-key:=[redacted] supersecret123`. The label is redacted but its value survives. `echo "sk-live-SECRET123"` also exposes the recognized token shape because the initial quote defeats prefix matching. These are synthetic test values. The resulting line is used for speech, the activity log, and session state.

Fix token-boundary handling, quoted credentials, and header/value association before truncation. Add regression cases for these exact inputs. Consider making program-only output the default, with command detail an explicit choice; its current implementation also needs review because a leading environment assignment can be mistaken for a program name. Pattern matching should remain documented as best-effort, not a secrecy guarantee.

### R2 — P2: repeated events erase reminder schedules

Location: [bin/iriscale-voice:1641](../../bin/iriscale-voice#L1641), with rearming at line 1829.

Reproduced by sending the same `PermissionRequest` twice, two seconds apart. The first state file contains `reminded=0` and `remind_at`; the second loses both, although cooldown correctly suppresses repeat speech. `state_write` reads the fields but never writes them back. Because status did not change, `since` remains old and the rearming condition fails. The watcher then has no next reminder.

Preserve lifecycle fields for same-status updates; reset them only at a deliberate state transition. Verify both duplicate events and actual new permission requests.

### R3 — P2: shared temporary state trusts pre-existing paths

Location: [bin/iriscale-voice:16](../../bin/iriscale-voice#L16).

Static finding: `$TMPDIR/iriscale-voice` (falling back to `/tmp/iriscale-voice`) is accepted if it is already a directory, including a symlink to one. Mode 700 only protects a directory this invocation successfully creates. On a shared temporary filesystem, another local user could pre-create the path to deny notifications or influence scratch-file destinations. This is primarily a shared Linux/fallback-`/tmp` concern; ordinary macOS temporary directories are already private per user. No multiuser exploit was executed.

Use a private user-specific runtime directory and validate ownership/type/permissions before reuse. Fail safely if it cannot be established.

### R4 — P2: macOS board opening does not escape installation paths

Location: [bin/iriscale-voice:1315](../../bin/iriscale-voice#L1315).

Static finding: the path is interpolated into an AppleScript string containing a shell command. An apostrophe in the installation or checkout directory breaks the shell quoting; a double quote breaks AppleScript quoting. Relative invocation paths also are not resolved before opening a new Terminal session. Errors are discarded while the command announces that the board opened.

Resolve an absolute path and pass it as an AppleScript argument, using AppleScript's shell-quoting facilities. Surface launch failures. Test quotes and spaces without opening a GUI, then smoke-test on a real Mac.

### R5 — P2: macOS speech diagnostics report success after failure

Location: [bin/iriscale-voice:813](../../bin/iriscale-voice#L813).

Reproduced with an isolated `uname` stub returning Darwin and a `say` stub exiting 42:

```text
spoke a test phrase via mac backend
exit_status=0
```

`cli_test` ignores `speak`'s status and returns success. This makes the principal troubleshooting command misleading when speech fails. Preserve the backend exit status and report a useful error; do the same for the speaker sample command. This is a control-flow reproduction, not a native Mac audio test.

No additional standards-only naming or abstraction concern was important enough to elevate above these defects. Keep fixes compatible with CONTRIBUTING.md's inexpensive hook path.

## Spec and installer behavior

### S1 — P1: valid TOML can cause unrelated Codex settings to be deleted

Location: [npm/codex.js:63](../../npm/codex.js#L63).

Reproduced with the real installer against an isolated Codex home. Starting with valid TOML:

```toml
notify = ["echo", "["]
model = "example-model"
[projects.foo]
trust_level = "trusted"
```

installation replaces the entire file with Iriscale's notify line. The bracket counter counts brackets inside strings and comments, so it mistakes unrelated trailing settings for part of the notify array. Backups provide possible manual recovery but do not make deletion acceptable.

Use a TOML-aware scanner/parser and reject uncertain input before writing. Preserve unrelated settings, comments, and multiline values; cover quoted brackets, comments, table-local keys, and literal strings.

### S2 — P1: the PowerShell installer removes other hooks

Locations: [install.ps1:230](../../install.ps1#L230), uninstall at line 71.

Static finding: installation replaces whole `UserPromptSubmit` and `PermissionRequest` events using `Add-Member -Force`. Uninstallation removes an entire event if its serialized value contains `iriscale-voice`. Existing logging, policy, or other notification hooks can disappear. This contradicts the documented promise to preserve user entries.

Merge and remove only owned handlers. The npm installer has a narrower sibling problem too: [npm/core.js:188](../../npm/core.js#L188) identifies an entire group as owned if any handler matches, so a user handler added alongside ours is lost on reinstall/uninstall. Preserve handlers within mixed groups.

### S3 — P1: PowerShell notify editing can make Codex configuration invalid

Location: [install.ps1:207](../../install.ps1#L207).

Static finding: only the first line of a multiline `notify` array is replaced, leaving its previous continuation lines and closing bracket. It also replaces table-local `notify` entries instead of ensuring a top-level entry. Uninstall removes the Iriscale line without restoring a displaced user notify command.

Bring PowerShell installation under the same configuration-preservation contract as npm, including restoration of displaced notify values. Run shared fixtures against both implementations.

### S4 — P2: the advertised npx update command does not update the runtime

Locations: [npm/cli.js:73](../../npm/cli.js#L73), README line 246, docs/install/npm.md line 83.

Static finding: `npx @iriscale/voice@latest update` normally runs from the npx cache. `update()` detects that this is not a global installation, prints instructions, and returns success without reapplying the installed agent configurations or refreshing their stable script. The README advertises this exact command as the npm update route.

Allow the current package to reapply recorded installations independently of upgrading a global npm package. Until then, document `npx @iriscale/voice@latest install codex --apply` (and the equivalent for Claude) as the update operation.

### S5 — P2: Codex never receives the permission-resolved transition

Locations: [npm/codex.js:11](../../npm/codex.js#L11), [bin/iriscale-voice:1519](../../bin/iriscale-voice#L1519).

Static integration finding: the Codex installer registers only prompt-start and permission-request hooks, plus completion through notify. The runtime's `resume` handler clears blocked state, but Codex is not configured to call it. After approval, a long-running tool/turn can remain shown as blocked and produce stale "needs your answer" reminders until completion or another prompt.

Current [official Codex hooks documentation](https://learn.chatgpt.com/docs/hooks) supports `PostToolUse`. Wire the existing transition and verify approval, rejection, and long-running tools against the supported Codex version. PostToolUse fires after tool completion, so it alone does not guarantee clearing the board immediately when a long-running approved tool starts. Document that timing honestly.

The [official notify contract](https://learn.chatgpt.com/docs/config-file/config-advanced) documents `agent-turn-complete`, not a general error stream. Explicitly show which attention/error events Codex supports rather than implying full Claude parity. The doctor's unconditional rejection of any `async=true` anywhere in hooks.json (line 1411) is also version-specific and can flag unrelated valid hooks; current documentation supports asynchronous hooks.

### S6 — P2: PowerShell launchers lose non-ASCII paths

Location: [install.ps1:174](../../install.ps1#L174).

Static finding: the absolute script path is written using ASCII. A profile directory such as `José` becomes `Jos?`, so the installed launcher cannot locate the script. The npm installer already uses `%~dp0iriscale-voice` to avoid embedding that path; apply the same approach to the PowerShell installer.

## A deliberately small improvement plan

1. **Protect installation and private data.** Fix R1 and S1–S3 first, with preservation/redaction fixtures. Make update actually refresh installed code (S4).
2. **Make existing notifications trustworthy.** Fix reminder persistence and Codex resume transitions. Test complete event sequences, including duplicates and long approval workflows, rather than only individual synthetic events.
3. **Make setup self-explanatory.** Extend the existing doctor/test commands to validate actual hook targets, supported agent versions, configuration structure, and speech exit status. Separate "configured", "trusted in the agent", and "speech backend succeeded"; do not claim that file inspection proves audio was heard.
4. **Close the Mac testing gap.** Keep the current macOS CI job and add path-escaping/backend-failure cases. Run a short real-Mac release checklist: install, restart/trust hooks, completion, permission, mute, select voice, concurrent notifications, update, uninstall with pre-existing configuration. Show only supported board actions: macOS focus is unimplemented and Codex rows have no recorded PID.
5. **Fix the few misleading commands.** README lines 127–128 and SECURITY.md lines 55–57 still use unscoped `iriscale-voice` npm commands; the manifest is `@iriscale/voice`. Use the exact scoped name everywhere. Do not infer that the unscoped package has the same owner or contents.

These are improvements to the core promise: tell the developer which session needs them, at the right time, without disrupting their existing setup. A tray app, additional agents, and AI-generated summaries can wait.
