#!/bin/sh
# Fires every event through every preset in debug mode (never speaks) and checks
# the decisions. Run from anywhere:  sh test/run.sh
# Uses a throwaway config so it never touches ~/.claude/iriscale-voice.conf.

here=$(cd "$(dirname "$0")" && pwd)
S="$here/../bin/iriscale-voice"
export IRISCALE_VOICE_DEBUG=1
export CLAUDE_CONFIG_DIR="${TMPDIR:-/tmp}/iriscale-voice-test-$$"
mkdir -p "$CLAUDE_CONFIG_DIR"
# The script keeps locks, turn clocks, last_prompt and the board pid under $TMPDIR/iriscale-voice.
# Point that at the sandbox too, so the suite never reads your live sessions' state (a
# 10-minute-old last_prompt made `stamp` print a welcome-back line and broke a capture)
# and never leaves its evil.start / brd-*.last files in yours.
export TMPDIR="$CLAUDE_CONFIG_DIR/tmp"; mkdir -p "$TMPDIR"
trap 'rm -rf "$CLAUDE_CONFIG_DIR" "${TMPDIR:-/tmp}/iriscale-voice/test-"*' EXIT
fail=0; pass=0
P='{"session_id":"test-sess","cwd":"/home/dev/my_service"}'

ok() { if [ "$1" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $3: got '$1' wanted '$2'"; fi; }
expect() {   # expect <SPEAK|SKIP> <event> [payload]
    want=$1; ev=$2; pl=${3:-$P}
    out=$(printf '%s' "$pl" | sh "$S" "$ev")
    case "$out" in
        "$want"*) pass=$((pass+1)) ;;
        *) fail=$((fail+1)); echo "FAIL [$ev] wanted $want, got: $out" ;;
    esac
}

echo "syntax:"; sh -n "$S" && bash --posix -n "$S" 2>/dev/null; echo "  ok"
sh "$S" set repeat_cooldown 0 >/dev/null     # the matrix below repeats lines on purpose

for preset in off basic standard verbose; do
    sh "$S" set preset $preset >/dev/null
    speaks=$(sh "$S" status | sed -n 's/.*speaks on: //p')      # once per preset, not per event
    for ev in Stop StopFailure PermissionRequest idle_prompt agent_completed SubagentStop SessionEnd; do
        case " $speaks " in
            *" $ev "*) expect SPEAK $ev ;;
            *)          expect SKIP  $ev ;;
        esac
    done
done

sh "$S" set preset standard >/dev/null
# permission phrasing
out=$(printf '%s' '{"session_id":"t","cwd":"/x/api","tool_name":"Bash","tool_input":{"command":"git push"}}' | sh "$S" PermissionRequest)
case "$out" in *"api is waiting for your answer to run git push"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL perm phrasing: $out" ;; esac
# PRIVACY: command_detail=redacted by default - the command is spoken, credentials are not
SECRETCMD='{"session_id":"t","cwd":"/x/api","tool_name":"Bash","tool_input":{"command":"curl -H \"Authorization: Bearer sk-live-abc123\" https://x.example"}}'
out=$(printf '%s' "$SECRETCMD" | sh "$S" PermissionRequest)
case "$out" in *"to run curl -H Authorization: Bearer [redacted]"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL redacted default: $out" ;; esac
case "$out" in *sk-live*) fail=$((fail+1)); echo "FAIL secret leaked by default: $out" ;; *) pass=$((pass+1)) ;; esac
out=$(printf '%s' '{"session_id":"t","cwd":"/x/api","tool_name":"Bash","tool_input":{"command":"psql postgres://admin:hunter2@db.internal/app"}}' | sh "$S" PermissionRequest)
case "$out" in *hunter2*) fail=$((fail+1)); echo "FAIL url password leaked: $out" ;; *"[redacted]@db.internal"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL url redaction shape: $out" ;; esac
out=$(printf '%s' '{"session_id":"t","cwd":"/x/api","tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}' | sh "$S" PermissionRequest)
case "$out" in *"to run git push origin main --force"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL harmless command must be spoken whole: $out" ;; esac
sh "$S" config set command_detail program >/dev/null
out=$(printf '%s' "$SECRETCMD" | sh "$S" PermissionRequest)
case "$out" in *"to run curl"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL program mode: $out" ;; esac
case "$out" in *Bearer*|*Authorization*) fail=$((fail+1)); echo "FAIL program mode spoke more than the program: $out" ;; *) pass=$((pass+1)) ;; esac
out=$(printf '%s' '{"session_id":"t","cwd":"/x/api","tool_name":"Bash","tool_input":{"command":"/usr/local/bin/npm run build --silent"}}' | sh "$S" PermissionRequest)
case "$out" in *"to run npm run"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL program mode basename+word: $out" ;; esac
sh "$S" config set command_detail full >/dev/null
out=$(printf '%s' "$SECRETCMD" | sh "$S" PermissionRequest)
case "$out" in *sk-live-abc123*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL full mode must be verbatim: $out" ;; esac
sh "$S" config unset command_detail >/dev/null
# SECURITY: session ids become file names - traversal must be neutralised
out=$(printf '%s' '{"session_id":"../../evil","cwd":"/x/api"}' | sh "$S" stamp >/dev/null; ls "${TMPDIR:-/tmp}/iriscale-voice/" | grep -c 'evil')
[ "$out" -ge 1 ] && [ ! -e "${TMPDIR:-/tmp}/evil.start" ]; ok $? 0 "traversal in session_id is neutralised"
# SECURITY: clean() must never admit quote/backslash/backtick/dollar (PowerShell single-quoted string)
out=$(printf '%s' '{"session_id":"q","cwd":"/x/a'"'"');calc;('"'"'b"}' | sh "$S" Stop)
case "$out" in *"'"*|*'`'*|*'$'*|*'\'*) fail=$((fail+1)); echo "FAIL clean() admitted a shell metachar: $out" ;; *) pass=$((pass+1)) ;; esac
# config values with sed metacharacters survive a round trip
sh "$S" config set voice 'a|b&c\d' >/dev/null; ok "$(sh "$S" config get voice)" 'a|b&c\d' "cfg_set keeps | & \\"; sh "$S" config unset voice >/dev/null
sh "$S" config set 'bad key' x >/dev/null 2>&1;             ok $? 2 "cfg_set rejects an invalid key"
# failure reason
out=$(printf '%s' '{"session_id":"t","cwd":"/x/api","reason":"rate_limit"}' | sh "$S" StopFailure)
case "$out" in *"stopped: rate limit"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL reason: $out" ;; esac
# duration gate: stamp then immediate Stop => SKIP; StopFailure still SPEAKs
printf '%s' "$P" | sh "$S" stamp
expect SKIP  Stop
expect SPEAK StopFailure
# overrides & gates
sh "$S" set event.SubagentStop on >/dev/null;  expect SPEAK SubagentStop; sh "$S" set event.SubagentStop "" >/dev/null
sh "$S" set quiet_hours 0-24 >/dev/null;       expect SKIP idle_prompt;   sh "$S" set quiet_hours "" >/dev/null
sh "$S" set mute_sessions my_service >/dev/null; expect SKIP idle_prompt; sh "$S" set mute_sessions "" >/dev/null
sh "$S" set only_sessions other >/dev/null;    expect SKIP idle_prompt;   sh "$S" set only_sessions "" >/dev/null
sh "$S" mute >/dev/null;                       expect SKIP idle_prompt;   sh "$S" unmute >/dev/null
# (not `VAR=1 expect ...`: in POSIX mode - dash, macOS sh - an assignment before a
# function call persists, which muted the rest of the suite on CI)
out=$(printf '%s' "$P" | env IRISCALE_VOICE_OFF=1 sh "$S" idle_prompt)
case "$out" in SKIP*IRISCALE_VOICE_OFF*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL env kill switch: $out" ;; esac
# name fallbacks
out=$(printf '%s' '{}' | sh "$S" idle_prompt); case "$out" in *"Claude is waiting"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL fallback: $out" ;; esac
out=$(printf '%s' '{"cwd":"C:\\w\\Some_App\\"}' | sh "$S" idle_prompt); case "$out" in *"Some App is waiting"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL win path: $out" ;; esac

# renamed session: current name must win over formerNames (regression)
mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
printf '%s' '{"pid":1,"sessionId":"renamed-1","cwd":"/x/y","name":"new_name","status":"idle","formerNames":[{"name":"old-name","renamedAt":1}]}' > "$CLAUDE_CONFIG_DIR/sessions/1.json"
out=$(printf '%s' '{"session_id":"renamed-1","cwd":"/x/y"}' | sh "$S" Stop)
case "$out" in *"new name done"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL renamed session: $out" ;; esac

# Codex CLI: /rename lives in ~/.codex/session_index.jsonl as {"id","thread_name"}
export CODEX_HOME="$CLAUDE_CONFIG_DIR/codex"; mkdir -p "$CODEX_HOME"
printf '%s\n%s\n' '{"id":"cdx-1","thread_name":"payments_api","updated_at":"x"}' '{"id":"cdx-2","thread_name":"other","updated_at":"x"}' > "$CODEX_HOME/session_index.jsonl"
out=$(printf '%s' '{"session_id":"cdx-1","cwd":"/x/repo","hook_event_name":"Stop","last_assistant_message":"ok"}' | sh "$S" Stop)
case "$out" in *"payments api done"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL codex rename: $out" ;; esac
out=$(printf '%s' '{"session_id":"cdx-9","cwd":"/x/repo"}' | sh "$S" Stop)   # unknown id -> folder
case "$out" in *"repo done"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL codex fallback: $out" ;; esac

# Other-agent aliases: event names, camelCase ids, and Cursor status/workspace roots.
sh "$S" set preset verbose >/dev/null
out=$(printf '%s' '{"sessionId":"cop-1","cwd":"/x/copilot_api"}' | sh "$S" agentStop)
case "$out" in *"copilot api done"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL Copilot agentStop: $out" ;; esac
out=$(printf '%s' '{"sessionId":"cop-2","cwd":"/x/copilot_api","error":"auth"}' | sh "$S" errorOccurred)
case "$out" in *"copilot api stopped: auth"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL Copilot errorOccurred: $out" ;; esac
out=$(printf '%s' '{"conversation_id":"cur-1","workspace_roots":["/x/cursor_app"],"status":"completed"}' | sh "$S" stop)
case "$out" in *"cursor app done"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL Cursor completed: $out" ;; esac
out=$(printf '%s' '{"conversation_id":"cur-2","workspace_roots":["/x/cursor_app"],"status":"error","error":"cancelled"}' | sh "$S" stop)
case "$out" in *"cursor app stopped with an error"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL Cursor error: $out" ;; esac
out=$(printf '%s' '{"conversation_id":"cur-3","workspace_roots":["/x/cursor_app"],"status":"aborted"}' | sh "$S" stop)
[ -z "$out" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL Cursor aborted should be silent: $out"; }
out=$(printf '%s' '{"session_id":"gem-1","cwd":"/x/gemini_cli"}' | sh "$S" AfterAgent)
case "$out" in *"gemini cli done"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL Gemini AfterAgent: $out" ;; esac

# Session state layer (feeds `sessions` / `board`): one key=value file per session.
SESSD="$CLAUDE_CONFIG_DIR/iriscale-voice-sessions"
sh "$S" set preset standard >/dev/null
B1='{"session_id":"brd-1","cwd":"/x/billing_service","hook_event_name":"UserPromptSubmit"}'
printf '%s' "$B1" | sh "$S" stamp
grep -q '^status=working' "$SESSD/brd-1";                 ok $? 0 "stamp -> state working"
grep -q '^agent=claude' "$SESSD/brd-1";                   ok $? 0 "claude-shaped payload -> agent=claude"
printf '%s' "$B1" | sh "$S" Stop >/dev/null
grep -q '^status=ready' "$SESSD/brd-1";                   ok $? 0 "Stop -> state ready"
sed 's/^since=.*/since=123/' "$SESSD/brd-1" > "$SESSD/brd-1.tmp" && mv "$SESSD/brd-1.tmp" "$SESSD/brd-1"   # no sed -i: BSD sed wants -i ''
printf '%s' "$B1" | sh "$S" Stop >/dev/null
grep -q '^since=123' "$SESSD/brd-1";                      ok $? 0 "unchanged status keeps since"
printf '%s' "$B1" | sh "$S" stamp; printf '%s' "$B1" | sh "$S" Stop >/dev/null   # fresh READY for the render checks below
printf '%s' '{"thread-id":"brd-2","cwd":"/x/payments_api","tool_name":"Bash","tool_input":{"command":"git push"}}' | sh "$S" PermissionRequest >/dev/null
grep -q '^status=blocked' "$SESSD/brd-2";                 ok $? 0 "PermissionRequest -> state blocked"
grep -q '^agent=codex' "$SESSD/brd-2";                    ok $? 0 "thread-id payload -> agent=codex"
grep -q '^said=payments api is waiting for your answer to run git push' "$SESSD/brd-2"; ok $? 0 "state records last said"
printf '%s' '{"session_id":"brd-3","cwd":"/x/data_migration","reason":"rate_limit"}' | sh "$S" StopFailure >/dev/null
grep -q '^status=error' "$SESSD/brd-3";                   ok $? 0 "StopFailure -> state error"
out=$(sh "$S" sessions --plain)
printf '%s' "$out" | grep -q 'payments_api.*NEEDS ANSWER'; ok $? 0 "sessions shows NEEDS ANSWER"
printf '%s' "$out" | grep -q 'billing_service.*READY';    ok $? 0 "sessions shows READY"
printf '%s' "$out" | grep -q 'data_migration.*NEEDS ACTION'; ok $? 0 "sessions shows NEEDS ACTION"
first=$(printf '%s' "$out" | grep -E 'payments_api|billing_service|data_migration' | head -n1)
case $first in *payments_api*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL blocked session must sort first: $first" ;; esac
printf '%s' "$out" | grep -q 'needs your answer';         ok $? 0 "sessions prints the legend"
case $out in *'[K'*) fail=$((fail+1)); echo "FAIL --plain output contains raw escape text" ;; *) pass=$((pass+1)) ;; esac
# colour path must emit REAL escape bytes (0.1.11 shipped '[32m' as text: ESC undefined)
esc_bytes=$(sh "$S" sessions --color | od -An -c | grep -c '033')
[ "$esc_bytes" -gt 0 ];                                   ok $? 0 "sessions --color emits escape bytes"
plain_esc=$(sh "$S" sessions --plain | od -An -c | grep -c '033')
[ "$plain_esc" -eq 0 ];                                   ok $? 0 "sessions --plain emits no escape bytes"
printf '%s' "$B1" | sh "$S" SessionEnd >/dev/null
[ ! -f "$SESSD/brd-1" ];                                  ok $? 0 "SessionEnd removes the state file"
sh "$S" board --once --plain >/dev/null 2>&1;             ok $? 0 "board --once exits"
# board autostart: off by default -> no attempt; on + board alive (pid file = this shell) -> no attempt; on + no board -> attempt
out=$(printf '%s' "$B1" | sh "$S" Stop); case "$out" in *board_autostart*) fail=$((fail+1)); echo "FAIL autostart fired while off: $out" ;; *) pass=$((pass+1)) ;; esac
sh "$S" config set board_autostart true >/dev/null
printf '%s\n' "$$" > "${TMPDIR:-/tmp}/iriscale-voice/board.pid"
out=$(printf '%s' "$B1" | sh "$S" Stop); case "$out" in *board_autostart*) fail=$((fail+1)); echo "FAIL autostart fired while a board is alive: $out" ;; *) pass=$((pass+1)) ;; esac
rm -f "${TMPDIR:-/tmp}/iriscale-voice/board.pid"
out=$(printf '%s' "$B1" | sh "$S" Stop); case "$out" in *"would open the board"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL autostart did not fire with no board: $out" ;; esac
sh "$S" config unset board_autostart >/dev/null
sh "$S" --help | grep -- '--open' >/dev/null;              ok $? 0 "help mentions board --open"
# click-to-focus: numbered rows, a rows map, and `focus` resolution
kout=$(sh "$S" sessions --keys --plain)
printf '%s' "$kout" | grep -q '^1 .*payments_api';        ok $? 0 "keys mode numbers the top row"
printf '%s' "$kout" | grep -q 'click a row or press';     ok $? 0 "keys mode explains the keys"
[ -f "${TMPDIR:-/tmp}/iriscale-voice/board.rows" ];       ok $? 0 "keys mode writes the rows map"
sh "$S" focus no_such_session >/dev/null 2>&1;            ok $? 1 "focus unknown session exits 1"
sh "$S" focus >/dev/null 2>&1;                            ok $? 2 "focus without target exits 2"
sh "$S" focus payments_api >/dev/null 2>&1;               ok $? 1 "focus session without pid exits 1 (codex: no pid yet)"
sh "$S" --help | grep 'focus <n|name|pid>' >/dev/null;    ok $? 0 "help lists focus"
sh "$S" sessions --plain | sed -n 1p | grep "v$(sh "$S" --version)" >/dev/null; ok $? 0 "board header shows the version"
sh "$S" sessions --plain | sed -n 1p | grep 'updated [0-9][0-9]:[0-9][0-9]:[0-9][0-9]' >/dev/null; ok $? 0 "board header labels the clock as 'updated'"
[ "$(sh "$S" sessions --keys --plain | grep 'bring it to the front' | awk '{print length}')" -le 80 ]; ok $? 0 "board footer fits 80 columns"

# repeat guard: same line twice inside the cooldown -> second is SKIP; a different line still SPEAKs
sh "$S" set repeat_cooldown 60 >/dev/null; sh "$S" set preset verbose >/dev/null
R='{"session_id":"loop-1","cwd":"/x/loopy"}'
expect SPEAK SubagentStop "$R"
expect SKIP  SubagentStop "$R"
expect SPEAK idle_prompt  "$R"
sh "$S" set repeat_cooldown 0 >/dev/null
# pronunciation: never say "subagent" as one word
out=$(printf '%s' '{"session_id":"p","cwd":"/x/y"}' | sh "$S" SubagentStop)
case "$out" in *"sub agent done"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL pronunciation: $out" ;; esac

# ---- CLI ----
sh "$S" --help >/dev/null 2>&1;            ok $? 0 "--help exit"
sh "$S" --help | grep '^USAGE' >/dev/null;         ok $? 0 "--help has USAGE"
sh "$S" -h    | grep 'config list' >/dev/null;     ok $? 0 "-h lists config"
sh "$S" '?'   | grep '^USAGE' >/dev/null;          ok $? 0 "? is a help alias"
sh "$S" --bogus >/dev/null 2>&1;           ok $? 2 "unknown option exits 2"
sh "$S" config nope >/dev/null 2>&1;       ok $? 2 "unknown config sub exits 2"
sh "$S" config set rate 3 >/dev/null;      ok "$(sh "$S" config get rate)" 3 "config set/get"
sh "$S" config unset rate >/dev/null;      ok "$(sh "$S" config get rate)" "(unset - using default)" "config unset"
ok "$(sh "$S" config path)" "$CLAUDE_CONFIG_DIR/iriscale-voice.conf" "config path"
sh "$S" config list | grep '^repeat_cooldown' >/dev/null;  ok $? 0 "config list has repeat_cooldown"
sh "$S" events | grep 'PermissionRequest' >/dev/null;      ok $? 0 "events lists PermissionRequest"
sh "$S" presets | grep '^  verbose' >/dev/null;            ok $? 0 "presets lists verbose"
install_out=$(sh "$S" install codex)
printf '%s' "$install_out" | grep '^notify = ' >/dev/null;  ok $? 0 "install codex prints notify config"
printf '%s' "$install_out" | grep 'UserPromptSubmit' >/dev/null; ok $? 0 "install codex prints full hooks"
printf '%s' "$install_out" | grep '"async"' >/dev/null; ok $? 1 "install codex prints synchronous hooks"
printf '%s' "$install_out" | grep "$here/../bin/iriscale-voice" >/dev/null; ok $? 1 "install codex normalizes script path"
[ ! -e "$CODEX_HOME/config.toml" ] && [ ! -e "$CODEX_HOME/hooks.json" ]; ok $? 0 "install codex never writes Codex config"
sh "$S" install unknown >/dev/null 2>&1;                    ok $? 2 "unknown install target exits 2"
cat > "$CODEX_HOME/config.toml" <<EOF
notify = ["$S", "notify"]
EOF
cat > "$CODEX_HOME/hooks.json" <<EOF
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"voice stamp"}]}],"PermissionRequest":[{"hooks":[{"type":"command","command":"voice PermissionRequest"}]}]}}
EOF
sh "$S" doctor codex | grep 'READY' >/dev/null;             ok $? 0 "doctor codex accepts synchronous hooks"
cat > "$CODEX_HOME/hooks.json" <<EOF
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","commandWindows":"voice stamp"}]}],"PermissionRequest":[{"hooks":[{"type":"command","commandWindows":"voice PermissionRequest"}]}]}}
EOF
sh "$S" doctor codex >/dev/null 2>&1;                       ok $? 1 "doctor codex rejects commandWindows-only hooks"
cat > "$CODEX_HOME/hooks.json" <<EOF
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"voice stamp"}]}],"PermissionRequest":[{"hooks":[{"type":"command","command":"voice PermissionRequest","async":true}]}]}}
EOF
sh "$S" doctor codex >/dev/null 2>&1;                       ok $? 1 "doctor codex rejects async hooks"
sh "$S" doctor unknown >/dev/null 2>&1;                     ok $? 2 "unknown doctor target exits 2"
sh "$S" completions powershell | grep 'Register-ArgumentCompleter' >/dev/null; ok $? 0 "PowerShell completion is available"
sh "$S" completions bash | grep 'complete -F' >/dev/null;   ok $? 0 "Bash completion is available"
sh "$S" completions zsh | grep '#compdef' >/dev/null;       ok $? 0 "Zsh completion is available"
sh "$S" completions nope >/dev/null 2>&1;                   ok $? 2 "unknown completion shell exits 2"
# version must agree in script, plugin.json, marketplace.json, package.json (release guard)
v_script=$(sh "$S" --version)
v_plugin=$(grep -o '"version": *"[^"]*"' "$here/../.claude-plugin/plugin.json"      | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
v_market=$(grep -o '"version": *"[^"]*"' "$here/../.claude-plugin/marketplace.json" | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
v_codex=$(grep -o '"version": *"[^"]*"' "$here/../.codex-plugin/plugin.json"       | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
ok "$v_plugin" "$v_script" "plugin.json version == script VERSION"
ok "$v_market" "$v_script" "marketplace.json version == script VERSION"
v_codex=$(grep -o '"version": *"[^"]*"' "$here/../.codex-plugin/plugin.json" | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
ok "$v_codex" "$v_script" ".codex-plugin/plugin.json version == script VERSION"
v_npm=$(grep -o '"version": *"[^"]*"' "$here/../package.json" | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
ok "$v_npm" "$v_script" "package.json version == script VERSION"
grep -q '"iriscale-voice": "npm/cli.js"' "$here/../package.json"; ok $? 0 "package.json exposes the iriscale-voice bin"
# the pinned install URLs and the installer's default -Ref must name this release
v_ref=$(grep -o "\[string\]\$Ref = 'v[^']*'" "$here/../install.ps1" | sed "s/.*'v\([^']*\)'/\1/")
ok "$v_ref" "$v_script" "install.ps1 -Ref default == script VERSION"
grep -q "releases/latest" "$here/../install.ps1";           ok $? 0 "install.ps1 -Update resolves the latest release (not the pinned ref)"
grep -q "iriscale_voice/v$v_script/install.ps1" "$here/../README.md";   ok $? 0 "README one-liner pins v$v_script"
grep -q "iriscale_voice/v$v_script/install.ps1" "$here/../SECURITY.md"; ok $? 0 "SECURITY.md pins v$v_script"
grep -q "iriscale_voice/v$v_script/install.ps1" "$here/../docs/install/codex.md"; ok $? 0 "docs/install/codex.md pins v$v_script"
# an unpinned installer URL means users run whatever main happens to be that minute
unpinned=$(grep -rl 'iriscale_voice/main/install.ps1' "$here/.." --include='*.md' 2>/dev/null | tr '\n' ' ')
ok "$unpinned" "" "no document ships an unpinned install.ps1 URL"
ok "$v_codex" "$v_script" "Codex plugin version == script VERSION"
[ -f "$here/../.codex-plugin/plugin.json" ];                ok $? 0 "Codex plugin manifest exists"
[ -f "$here/../skills/iriscale-voice/SKILL.md" ];           ok $? 0 "Codex skill exists"
grep -q '\$iriscale-voice' "$here/../skills/iriscale-voice/agents/openai.yaml"; ok $? 0 "Codex skill has invocation metadata"

# Windows one-command installer: isolate every write, include spaces in paths, and
# prove repeat installation preserves unrelated Codex configuration.
if command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
    PSROOT="$CLAUDE_CONFIG_DIR/installer space/iriscale-voice"
    PSCODEX="$CLAUDE_CONFIG_DIR/codex space"
    mkdir -p "$PSCODEX"
    printf '%s\n' '[model]' 'name = "keep-me"' > "$PSCODEX/config.toml"
    printf '%s\n' '{"hooks":{"OtherEvent":[{"hooks":[]}]}}' > "$PSCODEX/hooks.json"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$here/../install.ps1")" \
        -InstallRoot "$(cygpath -w "$PSROOT")" -CodexHome "$(cygpath -w "$PSCODEX")" \
        -SourcePath "$(cygpath -w "$here/..")" -SkipPath -SkipProfile >/dev/null
    ok $? 0 "PowerShell installer succeeds in paths with spaces"
    "$PSROOT/bin/iriscale-voice.cmd" --version | grep "^$v_script\$" >/dev/null
    ok $? 0 "installed Windows launcher runs"
    grep 'keep-me' "$PSCODEX/config.toml" >/dev/null && grep 'OtherEvent' "$PSCODEX/hooks.json" >/dev/null
    ok $? 0 "installer preserves unrelated Codex configuration"
    grep 'PermissionRequest' "$PSCODEX/hooks.json" >/dev/null && ! grep '"async"' "$PSCODEX/hooks.json" >/dev/null && \
        [ "$(grep -o '"command"[[:space:]]*:' "$PSCODEX/hooks.json" | wc -l | tr -d '[:space:]')" -eq 2 ]
    ok $? 0 "installer writes synchronous hooks with required command fields"
    grep 'name: iriscale-voice' "$PSCODEX/skills/iriscale-voice/SKILL.md" >/dev/null
    ok $? 0 "installer makes the Codex skill discoverable"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$here/../install.ps1")" \
        -InstallRoot "$(cygpath -w "$PSROOT")" -CodexHome "$(cygpath -w "$PSCODEX")" \
        -SourcePath "$(cygpath -w "$here/..")" -SkipPath -SkipProfile >/dev/null
    [ "$(grep -c '^notify = ' "$PSCODEX/config.toml")" -eq 1 ]; ok $? 0 "installer is idempotent"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$here/../install.ps1")" \
        -InstallRoot "$(cygpath -w "$PSROOT")" -CodexHome "$(cygpath -w "$PSCODEX")" \
        -Uninstall -SkipPath -SkipProfile >/dev/null
    [ ! -e "$PSROOT" ] && [ ! -e "$PSCODEX/skills/iriscale-voice" ] && grep 'keep-me' "$PSCODEX/config.toml" >/dev/null && \
        grep 'OtherEvent' "$PSCODEX/hooks.json" >/dev/null && ! grep 'PermissionRequest' "$PSCODEX/hooks.json" >/dev/null
    ok $? 0 "uninstaller removes only owned files and configuration"
fi
# every settings key documented in CONFIG.md
for k in $(sh "$S" config list | awk 'NR>1 && $1 !~ /^(file:|\(|$)/ {print $1}' | sed 's/\.<Event>//'); do
    grep -q "\`$k" "$here/../docs/CONFIG.md"; ok $? 0 "docs/CONFIG.md documents $k"
done

# Slash commands: one file per subcommand, always documented in the namespaced form
# /iriscale-voice:<name>. Never document a bare /<name> - Claude Code built-ins shadow
# bare plugin names (/voice was its dictation toggle; /status and /help are built-ins too).
for f in "$here"/../commands/*.md; do
    n=$(basename "$f" .md)
    if grep -En "(^|[^:a-z/-])/$n( |\`|$)" "$here"/../README.md "$here"/../docs/*.md >/dev/null 2>&1; then
        fail=$((fail+1)); echo "FAIL docs mention bare /$n - use /iriscale-voice:$n"
    else pass=$((pass+1)); fi
    grep -q "^description:" "$f"; ok $? 0 "commands/$n.md has a description"
done

# Performance guard: the hook path must stay nearly spawn-free (each external process
# costs 25-50 ms on Windows/MSYS; v0.1.4 spawned ~40 and took 1.8 s per event).
# Count externals by putting logging shims for the usual suspects first on PATH.
SHIM="$CLAUDE_CONFIG_DIR/shim"; mkdir -p "$SHIM"; : > "$SHIM/.log"
for tool in sed grep tr awk cut head tail cat find; do
    real=$(command -v $tool)
    printf '#!/bin/sh\necho %s >> "%s"\nexec "%s" "$@"\n' "$tool" "$SHIM/.log" "$real" > "$SHIM/$tool"; chmod +x "$SHIM/$tool"
done
sh "$S" set preset standard >/dev/null; : > "$SHIM/.log"
printf '%s' '{"session_id":"perf-1","cwd":"/x/perf_svc","tool_name":"Bash","tool_input":{"command":"ls"}}' | PATH="$SHIM:$PATH" sh "$S" PermissionRequest >/dev/null
spawns=$(wc -l < "$SHIM/.log" | tr -d ' ')
if [ "$spawns" -le 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL hook path spawned $spawns text-tool processes (limit 1): $(sort "$SHIM/.log" | uniq -c | tr '\n' ' ')"; fi
# resume runs on EVERY tool call (PostToolUse), on a blocked row here so the write path is measured
: > "$SHIM/.log"
printf '%s' '{"session_id":"perf-1","cwd":"/x/perf_svc","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"stdout":"a\nb"}}' | PATH="$SHIM:$PATH" sh "$S" resume >/dev/null
spawns=$(wc -l < "$SHIM/.log" | tr -d ' ')
if [ "$spawns" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL resume (every tool call) spawned $spawns text-tool processes (limit 0): $(sort "$SHIM/.log" | uniq -c | tr '\n' ' ')"; fi
grep -q '^status=working' "$SESSD/perf-1";                   ok $? 0 "perf: resume did clear the blocked row it was measured on"

# Non-blocking speech guard: hosts that run hooks synchronously (Codex) must get the
# hook back in well under a second even though speaking takes seconds. Stub every
# speech backend with a 3 s sleep; the script must return without waiting for it.
for spk in powershell.exe say spd-say espeak-ng espeak notify-send; do
    printf '#!/bin/sh\nsleep 3\n' > "$SHIM/$spk"; chmod +x "$SHIM/$spk"
done
t0=$(date +%s)
printf '%s' '{"session_id":"sync-1","cwd":"/x/sync_host"}' | IRISCALE_VOICE_DEBUG= PATH="$SHIM:$PATH" sh "$S" Stop >/dev/null 2>&1
t1=$(date +%s)
if [ $((t1 - t0)) -le 2 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL hook blocked $((t1 - t0))s on speech - must background the speaker (limit 2s; the bug was 7s)"; fi
sleep 4   # let the stubbed background speaker finish before the trap cleans the shim dir

# Speech clarity: what the synthesizer actually receives. Debug prints it as "spoken as:".
sh "$S" set preset standard >/dev/null; sh "$S" set repeat_cooldown 0 >/dev/null
spoken() { printf '%s' "$1" | sh "$S" "$2" | sed -n 's/^      spoken as: //p'; }
out=$(spoken '{"session_id":"sp-1","cwd":"/x/iriscale-voice-4d","tool_name":"AskUserQuestion"}' PermissionRequest)
ok "$out" "iris scale voice 4 D, is waiting for your answer to use Ask User Question" "spoken: pause after the name, hash suffix spelled, CamelCase split"
out=$(spoken '{"session_id":"sp-2","cwd":"/x/payments_api","tool_name":"Bash","tool_input":{"command":"npx eslint src && kubectl get pods"}}' PermissionRequest)
ok "$out" "payments A P I, is waiting for your answer to run N P X E S lint src and then kube control get pods" "spoken: CLI names said the human way"
out=$(spoken '{"session_id":"sp-3","cwd":"/x/bad-cafe-0f","tool_name":"WebFetch"}' PermissionRequest)
ok "$out" "bad cafe 0 F, is waiting for your answer to use Web Fetch" "spoken: real hex-looking words stay words, 0f is spelled"
out=$(spoken '{"session_id":"sp-4","cwd":"/x/billing"}' Stop)
ok "$out" "billing, done" "spoken: an ordinary name is only given its pause"
# a range like [a-z] is matched by the locale's COLLATION: in a UTF-8 locale [A-Z] also
# matches lowercase letters, which spelled every word out ("pa y m e n t s"). A locale the
# machine does not have falls back to C, so this is safe to run anywhere.
for loc in C en_US.UTF-8; do
    out=$(printf '%s' '{"session_id":"sp-4l","cwd":"/x/payments_api","tool_name":"WebFetch"}' | LC_ALL=$loc sh "$S" PermissionRequest | sed -n 's/^      spoken as: //p')
    ok "$out" "payments A P I, is waiting for your answer to use Web Fetch" "spoken form does not depend on the locale ($loc)"
done
out=$(printf '%s' '{"session_id":"sp-4","cwd":"/x/billing"}' | sh "$S" Stop | head -1)
ok "$out" "SPEAK [Stop] billing done" "the logged/board line stays plain"
sh "$S" set pronounce "Iriscale=eye riss scale, naro=nah row" >/dev/null
out=$(spoken '{"session_id":"sp-1","cwd":"/x/iriscale-voice-4d"}' Stop)
ok "$out" "eye riss scale voice 4 D, done" "pronounce: your word wins over the built-in list, any case, spaces around the pair"
sh "$S" set pronounce "iriscale=x'y\$z\`w\\v" >/dev/null
out=$(spoken '{"session_id":"sp-1","cwd":"/x/iriscale-voice-4d"}' Stop)
case "$out" in *"'"*|*'`'*|*'$'*|*'\'*) fail=$((fail+1)); echo "FAIL pronounce value reached the speaker unscrubbed: $out" ;; *) pass=$((pass+1)) ;; esac
sh "$S" unset pronounce >/dev/null
out=$(printf '%s' '{"session_id":"sp-5","message":"payments still needs your answer, 3 minutes"}' | sh "$S" Remind | head -1)
ok "$out" "SPEAK [Remind] payments still needs your answer, 3 minutes" "a reminder line is spoken whole (no extra pause)"
# voice names: macOS lists its clearer voices as "Eddy (English (US))"; those must reach say.
VSHIM="$CLAUDE_CONFIG_DIR/vshim"; mkdir -p "$VSHIM"
for spk in say spd-say espeak-ng espeak powershell.exe; do
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s/say.log"\n' "$VSHIM" > "$VSHIM/$spk"; chmod +x "$VSHIM/$spk"
done
say_args() { : > "$VSHIM/say.log"; IRISCALE_VOICE_DEBUG= PATH="$VSHIM:$PATH" sh "$S" say "$@" >/dev/null 2>&1; cat "$VSHIM/say.log"; }
case "$(uname -s 2>/dev/null)" in
    Linux) pass=$((pass+2)) ;;   # the voice key is ignored on Linux
    *)  sh "$S" set voice "Eddy (English (US))" >/dev/null
        case "$(say_args hello)" in *"Eddy (English (US))"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL a voice name with parentheses must reach the speaker: $(cat "$VSHIM/say.log")" ;; esac
        sh "$S" set voice "Eddy's (US)" >/dev/null
        case "$(say_args hello)" in *Eddy*) fail=$((fail+1)); echo "FAIL a voice name with a quote must be dropped: $(cat "$VSHIM/say.log")" ;; *) pass=$((pass+1)) ;; esac
        sh "$S" unset voice >/dev/null ;;
esac
case "$(say_args "AskUserQuestion npx")" in *"Ask User Question N P X"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL say <text> is normalised too: $(cat "$VSHIM/say.log")" ;; esac
PATH="$VSHIM:$PATH" sh "$S" speaker >/dev/null 2>&1;        ok $? 0 "speaker exits 0"
# on Linux the voice belongs to speech-dispatcher/espeak, so the list says so instead
case "$(uname -s 2>/dev/null)" in Linux) LISTHINT='spd-conf' ;; *) LISTHINT='iriscale-voice speaker' ;; esac
PATH="$VSHIM:$PATH" sh "$S" speaker 2>/dev/null | grep -q "$LISTHINT"; ok $? 0 "the list tells you where the voice comes from"
sh "$S" completions powershell | grep -q "'voices'";          ok $? 0 "completions keep the voices alias"
# /iriscale-voice:speaker - list, set (and hear a sample), refuse junk, go back to default
PATH="$VSHIM:$PATH" sh "$S" speaker 2>/dev/null | grep -q "$LISTHINT"; ok $? 0 "speaker with no argument lists the voices"
PATH="$VSHIM:$PATH" sh "$S" voices 2>/dev/null | grep -q "$LISTHINT"; ok $? 0 "voices is the same list (the word people reach for)"
: > "$VSHIM/say.log"
IRISCALE_VOICE_DEBUG= PATH="$VSHIM:$PATH" sh "$S" speaker "Eddy (English (US))" >/dev/null 2>&1;  ok $? 0 "speaker <name> exit status"
ok "$(sh "$S" config get voice)" "Eddy (English (US))" "speaker <name> stores the name (parentheses and all)"
case "$(uname -s 2>/dev/null)" in Linux) pass=$((pass+1)) ;; *)
    case "$(cat "$VSHIM/say.log")" in *"Eddy (English (US))"*"sounds like this"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL speaker <name> must speak a sample in that voice: $(cat "$VSHIM/say.log")" ;; esac ;;
esac
IRISCALE_VOICE_DEBUG= PATH="$VSHIM:$PATH" sh "$S" speaker "Eddy's" >/dev/null 2>&1;           ok $? 2 "speaker refuses a name with a quote"
ok "$(sh "$S" config get voice)" "Eddy (English (US))" "a refused name leaves the setting alone"
sh "$S" mute >/dev/null
: > "$VSHIM/say.log"; IRISCALE_VOICE_DEBUG= PATH="$VSHIM:$PATH" sh "$S" speaker "Samantha" | grep -q muted; ok $? 0 "speaker <name> honours mute (no sample)"
case "$(cat "$VSHIM/say.log")" in *"sounds like this"*) fail=$((fail+1)); echo "FAIL a muted speaker <name> must not speak the sample" ;; *) pass=$((pass+1)) ;; esac
sh "$S" unmute >/dev/null
sh "$S" speaker default >/dev/null;                           ok "$(sh "$S" config get voice)" "(unset - using default)" "speaker default restores the system voice"
sh "$S" completions powershell | grep -q "'speaker'";         ok $? 0 "completions list speaker"
# the default list is a shortlist: macOS installs ~40 English voices and most are toys.
VLIST="$CLAUDE_CONFIG_DIR/vlist"; mkdir -p "$VLIST"
cat > "$VLIST/say" <<'SAYEOF'
#!/bin/sh
[ "$1" = "-v" ] && [ "$2" = "?" ] || exit 0
printf '%s\n' "Samantha            en_US    # Hello!" \
               "Zarvox              en_US    # Hello!" \
               "Aman (English (India)) en_IN    # Hello!" \
               "Aman (English (India)) en_IN    # Hi, I am Siri!" \
               "Anna                de_DE    # Hallo!"
SAYEOF
chmod +x "$VLIST/say"
case "$(uname -s 2>/dev/null)" in
    Darwin)
        vout=$(PATH="$VLIST:$PATH" sh "$S" speaker 2>/dev/null)
        case "$vout" in *Samantha*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL the shortlist must offer Samantha: $vout" ;; esac
        printf '%s\n' "$vout" | grep -q '^  Zarvox'; [ $? = 1 ]; ok $? 0 "a novelty voice is not offered in the shortlist"
        printf '%s\n' "$vout" | grep -q '^  Anna';   [ $? = 1 ]; ok $? 0 "a non-English voice is never listed"
        ok "$(printf '%s\n' "$vout" | grep -c 'Aman')" "1" "a voice macOS lists twice (its Siri variant) is shown once"
        case "$vout" in *"speaker --all"*"3 installed"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL the shortlist must say how to see the rest, and how many: $vout" ;; esac
        vall=$(PATH="$VLIST:$PATH" sh "$S" speaker --all 2>/dev/null)
        case "$vall" in *Zarvox*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL --all must list every voice: $vall" ;; esac
        case "$(PATH="$VLIST:$PATH" sh "$S" voices --all 2>/dev/null)" in *Zarvox*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL voices --all must list every voice" ;; esac
        # it is read in a terminal pane and pasted into chat windows that do not wrap
        wide=$(printf '%s\n' "$vout" "$vall" | awk '{ if (length($0) > m) { m = length($0); l = $0 } } END { if (m > 80) print m ": " l }')
        [ -z "$wide" ]; ok $? 0 "every line of the voice list fits 80 columns${wide:+ - $wide}" ;;
    *)  pass=$((pass+8)) ;;
esac

# `test` (the CLI diagnostic) must honor mute, not just hook events (regression: it used
# to call the speech backend unconditionally, so `mute` could not be trusted to mean
# "totally silent" - see the muted-test-still-spoke report).
for spk in powershell.exe say spd-say espeak-ng espeak; do
    printf '#!/bin/sh\necho spoke >> "%s"\n' "$SHIM/.speak.log" > "$SHIM/$spk"; chmod +x "$SHIM/$spk"
done
sh "$S" mute >/dev/null; : > "$SHIM/.speak.log"
out=$(PATH="$SHIM:$PATH" sh "$S" test)
case "$out" in muted*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL muted \`test\` must say so, not attempt speech: $out" ;; esac
[ -s "$SHIM/.speak.log" ] && { fail=$((fail+1)); echo "FAIL \`test\` called the speech backend while muted"; } || pass=$((pass+1))
sh "$S" unmute >/dev/null; : > "$SHIM/.speak.log"
out=$(PATH="$SHIM:$PATH" sh "$S" test)
case "$out" in "spoke a test phrase"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL unmuted \`test\` must still speak: $out" ;; esac
[ -s "$SHIM/.speak.log" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL \`test\` did not call the speech backend once unmuted"; }

# Degraded-environment guards (Codex launched the raw MSYS sh.exe with no /usr/bin on
# PATH: date/uname/tr were all missing and hooks errored or mis-suppressed).
# 1. os() must answer from $OS without uname.
out=$(OS=Windows_NT sh "$S" status | sed -n "s/.*os: //p")
ok "${out%% *}" "win" "os() trusts \ without uname"
# 2. A dead clock must skip quiet hours, not treat the time as midnight.
printf '#!/bin/sh
exit 1
' > "$SHIM/date"; chmod +x "$SHIM/date"
sh "$S" set quiet_hours 0-23 >/dev/null
out=$(printf '%s' '{"session_id":"noclock","cwd":"/x/no_clock"}' | PATH="$SHIM:$PATH" sh "$S" Stop)
case "$out" in SPEAK*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL dead clock must not suppress: $out" ;; esac
sh "$S" set quiet_hours "" >/dev/null; rm -f "$SHIM/date"
# 3. install codex must never print the raw usr/bin sh (no PATH when launched from Windows).
if [ "$(sh "$S" status | sed -n "s/.*os: //p" | sed "s/ .*//")" = win ]; then
    sh "$S" install codex | grep "usr/bin/sh.exe" >/dev/null && { fail=$((fail+1)); echo "FAIL install codex printed raw usr/bin/sh.exe"; } || pass=$((pass+1))
fi

# Board hygiene: `sessions` forgets a session whose process is gone; a pid-less row (Codex,
# a hand-fed event) stays while fresh and is forgotten after board_hide_hours; `forget`
# drops rows by name or all at once.
sh -c "exit 0" & deadpid=$!; wait "$deadpid" 2>/dev/null || :
printf "agent=claude
name=gone_session
status=ready
since=1
updated=%s
pid=%s
cwd=/x
said=
" "$(date +%s)" "$deadpid" > "$SESSD/prune-1"
printf "agent=codex
name=fresh_codex
status=waiting
since=1
updated=%s
pid=
cwd=/x
said=
" "$(date +%s)" > "$SESSD/prune-2"
printf "agent=agent
name=ancient_row
status=ready
since=1
updated=1
pid=
cwd=/x
said=
" > "$SESSD/prune-3"
printf "agent=claude
name=live_session
status=working
since=1
updated=%s
pid=%s
cwd=/x
said=
" "$(date +%s)" "$$" > "$SESSD/prune-4"
out=$(sh "$S" sessions --plain)
[ ! -f "$SESSD/prune-1" ];                               ok $? 0 "sessions forgets a session whose process is gone"
[ -f "$SESSD/prune-2" ];                                 ok $? 0 "sessions keeps a fresh session with no pid (Codex)"
[ ! -f "$SESSD/prune-3" ];                               ok $? 0 "sessions forgets a pid-less session older than board_hide_hours"
[ -f "$SESSD/prune-4" ];                                 ok $? 0 "sessions keeps a session whose process is alive"
printf "%s" "$out" | grep -q live_session;                 ok $? 0 "the live session is listed"
printf "%s" "$out" | grep -q gone_session;                 ok $? 1 "the gone session is not listed"
sh "$S" forget fresh_codex | grep -q "forgot 1";           ok $? 0 "forget <name> drops that row"
[ ! -f "$SESSD/prune-2" ];                               ok $? 0 "forget removed the state file"
sh "$S" forget --all >/dev/null; [ -z "$(ls "$SESSD" 2>/dev/null)" ]; ok $? 0 "forget --all empties the board"
sh "$S" forget >/dev/null 2>&1;                            ok $? 2 "forget with no argument is usage (exit 2)"
sh "$S" --help | grep -q "forget <name";                   ok $? 0 "help lists forget"

# Volume Mixer verdicts (Windows): pure string logic, checked everywhere via the hidden mixer-verdict entry.
sh "$S" mixer-verdict "app=0 appmuted=False master=50 mastermuted=False fixed=False" | grep -q "at 0% in the Volume Mixer.*test --fix"; ok $? 0 "mixer: 0% app level warns and names test --fix"
sh "$S" mixer-verdict "app=100 appmuted=True master=50 mastermuted=False fixed=False" | grep -q "muted in the Volume Mixer"; ok $? 0 "mixer: muted app warns"
[ -z "$(sh "$S" mixer-verdict "app=100 appmuted=False master=50 mastermuted=False fixed=False")" ]; ok $? 0 "mixer: healthy levels print nothing"
sh "$S" mixer-verdict "app=12 appmuted=False master=50 mastermuted=False fixed=False" | grep -q "note: Windows PowerShell is at 12%"; ok $? 0 "mixer: low app level is a note"
sh "$S" mixer-verdict "app=100 appmuted=False master=50 mastermuted=False fixed=True" | grep -q "restored Windows PowerShell to 100%"; ok $? 0 "mixer: --fix reports the restore"
sh "$S" mixer-verdict "app=100 appmuted=False master=0 mastermuted=True fixed=False" | grep -q "output device is muted"; ok $? 0 "mixer: muted output device warns"
sh "$S" mixer-verdict "app=? appmuted=? master=? mastermuted=? fixed=False" | grep -q .; ok $? 1 "mixer: unknown report prints nothing"
sh "$S" --help | grep -q "test \[--fix\]"; ok $? 0 "help documents test --fix"
grep -q 'test $ARGUMENTS' "$here/../commands/test.md"; ok $? 0 "/iriscale-voice:test passes arguments through"

# Background-aware Stop: Claude Code (2.1+) sends background_tasks / session_crons on Stop.
# A Stop with work in flight is a pause (StepDone, verbose only), not "done"; the turn
# clock survives Claude's own wake-ups so "done after N minutes" covers the whole job.
sh "$S" set preset standard >/dev/null
BGDIR="${TMPDIR:-/tmp}/iriscale-voice"
BG1='{"session_id":"bg-1","cwd":"/x/repo_digest","hook_event_name":"Stop","background_tasks":[{"id":"a1","type":"subagent","status":"running","description":"Repo digest: engine pin selection methodology","agent_type":"general-purpose"}],"session_crons":[]}'
BG2='{"session_id":"bg-1","cwd":"/x/repo_digest","hook_event_name":"Stop","background_tasks":[{"id":"a1","type":"subagent","status":"running","description":"Repo digest"},{"id":"s1","type":"shell","status":"running","description":"pnpm test","command":"pnpm test"}],"session_crons":[]}'
BG0='{"session_id":"bg-1","cwd":"/x/repo_digest","hook_event_name":"Stop","background_tasks":[],"session_crons":[]}'
BGC='{"session_id":"bg-1","cwd":"/x/repo_digest","hook_event_name":"Stop","background_tasks":[],"session_crons":[{"id":"c1","schedule":"*/20 * * * *","recurring":true,"prompt":"check ci"}]}'
BGX='{"session_id":"bg-1","cwd":"/x/repo_digest","hook_event_name":"Stop"}'
printf '%s\n' "$(( $(date +%s) - 400 ))" > "$BGDIR/bg-1.start"; started=$(cat "$BGDIR/bg-1.start")
out=$(printf '%s' "$BG1" | sh "$S" Stop)
case "$out" in "SKIP  [StepDone]"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL Stop with background work must be a silent StepDone: $out" ;; esac
grep -q '^status=working' "$SESSD/bg-1";                                          ok $? 0 "background work -> board stays working"
grep -q '^note=waiting for 1 agent: Repo digest: engine pin selection methodology' "$SESSD/bg-1"; ok $? 0 "board note names the agent"
out=$(printf '%s' '{"session_id":"bg-1","cwd":"/x/repo_digest","hook_event_name":"UserPromptSubmit","source":"system","prompt":"agent finished"}' | sh "$S" stamp)
[ "$(cat "$BGDIR/bg-1.start")" = "$started" ];                                       ok $? 0 "a system wake-up keeps the original turn start"
out=$(printf '%s' "$BG0" | sh "$S" Stop)
case "$out" in *"repo digest done after 6 minutes"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL final Stop must speak done with the whole elapsed time: $out" ;; esac
grep -q '^status=ready' "$SESSD/bg-1";                                            ok $? 0 "empty background_tasks -> ready"
grep -q '^note=$' "$SESSD/bg-1";                                                  ok $? 0 "note cleared when the work is done"
out=$(printf '%s' '{"session_id":"bg-1","cwd":"/x/repo_digest","hook_event_name":"UserPromptSubmit","source":"user","prompt":"next"}' | sh "$S" stamp)
[ "$(cat "$BGDIR/bg-1.start")" != "$started" ];                                      ok $? 0 "a real prompt restarts the turn clock"
printf '%s
' "$(( $(date +%s) - 400 ))" > "$BGDIR/bg-1.start"   # a real turn, not the 2 s since the stamp above
out=$(printf '%s' "$BGX" | sh "$S" Stop)
case "$out" in "SPEAK [Stop]"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL Stop without the field (older host) must behave as before: $out" ;; esac
out=$(printf '%s' "$BGC" | sh "$S" Stop)
case "$out" in "SKIP  [Scheduled]"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL Stop with a pending cron must be a silent Scheduled: $out" ;; esac
grep -q '^status=scheduled' "$SESSD/bg-1";                                        ok $? 0 "pending cron -> board scheduled"
sh "$S" sessions --plain | grep -q 'repo_digest.*scheduled.*paused until its next wake-up'; ok $? 0 "board shows scheduled with its note"
sh "$S" set preset verbose >/dev/null
out=$(printf '%s' "$BG1" | sh "$S" Stop)
case "$out" in *"repo digest finished a step, 1 agent still running"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL verbose StepDone phrasing: $out" ;; esac
out=$(printf '%s' "$BG2" | sh "$S" Stop)
case "$out" in *"finished a step, 2 background tasks still running"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL verbose StepDone counts tasks: $out" ;; esac
out=$(printf '%s' "$BGC" | sh "$S" Stop)
case "$out" in *"repo digest paused until its next wake-up"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL verbose Scheduled phrasing: $out" ;; esac
sh "$S" set preset standard >/dev/null
sh "$S" events | grep -q '^  StepDone';                                          ok $? 0 "events table lists StepDone"
rm -f "$BGDIR/bg-1.start"

# Passive review lifecycle (0.1.23). Driven through `tick` so nothing sleeps.
sh "$S" set preset standard >/dev/null; sh "$S" set repeat_cooldown 0 >/dev/null
LCDIR="${TMPDIR:-/tmp}/iriscale-voice"; rm -f "$LCDIR/last_prompt"
LC1='{"session_id":"lc-1","cwd":"/x/billing","hook_event_name":"Stop","background_tasks":[],"session_crons":[]}'
LC2='{"session_id":"lc-2","cwd":"/x/payments","tool_name":"Bash","tool_input":{"command":"git push"}}'
LC3='{"session_id":"lc-3","cwd":"/x/migration","reason":"rate_limit"}'
printf '%s' '{"session_id":"lc-1","cwd":"/x/billing","hook_event_name":"UserPromptSubmit","source":"user"}' | sh "$S" stamp >/dev/null
printf '%s' "$LC1" | sh "$S" Stop >/dev/null
grep -q '^status=ready' "$SESSD/lc-1";                       ok $? 0 "lifecycle: Stop -> ready"
grep -q '^reminded=0' "$SESSD/lc-1";                         ok $? 0 "lifecycle: Stop arms the reminder counter"
ra=$(sed -n 's/^remind_at=//p' "$SESSD/lc-1"); since=$(sed -n 's/^since=//p' "$SESSD/lc-1")
[ "$ra" = "$((since + 900))" ];                              ok $? 0 "lifecycle: standard review reminder is 15 min after the turn end"
# the state file says agent=claude only for payloads shaped like Claude's; brd payloads carried hook_event_name
grep -q '^agent=claude' "$SESSD/lc-1";                       ok $? 0 "lifecycle: Claude-shaped payload -> agent=claude"
# 1. reviewed: READY outlives the idle window with no idle notice -> a key was pressed there
sh "$S" tick lc-1 >/dev/null; grep -q '^status=ready' "$SESSD/lc-1";   ok $? 0 "tick inside the idle window leaves READY alone"
old=$(( $(date +%s) - 200 )); sed "s/^since=.*/since=$old/" "$SESSD/lc-1" > "$SESSD/lc-1.tmp" && mv "$SESSD/lc-1.tmp" "$SESSD/lc-1"
out=$(sh "$S" tick lc-1); grep -q '^status=reviewed' "$SESSD/lc-1";   ok $? 0 "tick past the idle window -> reviewed (no idle notice = key pressed)"
grep -q '^remind_at=$' "$SESSD/lc-1";                        ok $? 0 "reviewed clears the reminder"
sh "$S" sessions --plain | grep -q 'billing.*reviewed';       ok $? 0 "board shows reviewed"
# 2. the idle notice arrives instead -> needs your review; it never demotes a permission prompt
printf '%s' "$LC1" | sh "$S" Stop >/dev/null
printf '%s' '{"session_id":"lc-1","cwd":"/x/billing","hook_event_name":"Notification","notification_type":"idle_prompt"}' | sh "$S" idle_prompt >/dev/null
grep -q '^status=review' "$SESSD/lc-1";                      ok $? 0 "idle notice on READY -> needs your review"
printf '%s' "$LC2" | sh "$S" PermissionRequest >/dev/null
printf '%s' '{"session_id":"lc-2","cwd":"/x/payments"}' | sh "$S" idle_prompt >/dev/null
grep -q '^status=blocked' "$SESSD/lc-2";                     ok $? 0 "idle notice never demotes needs-your-answer"
ra=$(sed -n 's/^remind_at=//p' "$SESSD/lc-2"); since=$(sed -n 's/^since=//p' "$SESSD/lc-2")
[ "$ra" = "$((since + 180))" ];                              ok $? 0 "standard answer reminder is 3 min after the prompt"
# 3. one reminder due -> one line with the age; counter and next time advance
rm -f "$LCDIR/last_prompt"   # the stamp above counted as activity; reminders must not be paused here
now=$(date +%s); sed "s/^remind_at=.*/remind_at=$((now - 5))/; s/^since=.*/since=$((now - 600))/" "$SESSD/lc-2" > "$SESSD/lc-2.tmp" && mv "$SESSD/lc-2.tmp" "$SESSD/lc-2"
out=$(sh "$S" tick lc-2)
case "$out" in *"SPEAK [Remind] payments still needs your answer, 10 minutes"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL single reminder: $out" ;; esac
grep -q '^reminded=1' "$SESSD/lc-2";                         ok $? 0 "reminder counted"
[ "$(sed -n 's/^remind_at=//p' "$SESSD/lc-2")" = "$((now - 600 + 600))" ]; ok $? 0 "second answer reminder lands at +10 min from the prompt"
# 4. two due at once -> merged into one line, both counted; caps clear remind_at
sed "s/^remind_at=.*/remind_at=$((now - 5))/" "$SESSD/lc-2" > "$SESSD/lc-2.tmp" && mv "$SESSD/lc-2.tmp" "$SESSD/lc-2"
sed "s/^remind_at=.*/remind_at=$((now - 5))/; s/^since=.*/since=$((now - 1000))/" "$SESSD/lc-1" > "$SESSD/lc-1.tmp" && mv "$SESSD/lc-1.tmp" "$SESSD/lc-1"
out=$(sh "$S" tick lc-1)
case "$out" in *"SPEAK [Remind] still waiting: billing ready for review, payments needs your answer"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL merged reminder: $out" ;; esac
grep -q '^remind_at=$' "$SESSD/lc-1";                        ok $? 0 "review reminder capped after one (standard)"
grep -q '^remind_at=$' "$SESSD/lc-2";                        ok $? 0 "answer reminders capped after two (standard)"
out=$(sh "$S" tick lc-1); case "$out" in *SPEAK*) fail=$((fail+1)); echo "FAIL capped reminders must stay silent: $out" ;; *) pass=$((pass+1)) ;; esac
# 5. active elsewhere -> the step is skipped, not deferred
printf '%s' "$LC3" | sh "$S" StopFailure >/dev/null
sed "s/^remind_at=.*/remind_at=$((now - 5))/" "$SESSD/lc-3" > "$SESSD/lc-3.tmp" && mv "$SESSD/lc-3.tmp" "$SESSD/lc-3"
printf '%s\n' "$now" > "$LCDIR/last_prompt"
out=$(sh "$S" tick lc-3)
case "$out" in *remind_pause*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL remind_pause must skip while you are active: $out" ;; esac
grep -q '^reminded=1' "$SESSD/lc-3";                         ok $? 0 "a skipped reminder still counts"
# 6. presets and overrides
# reminders are (re)armed when the status changes, as in real life a prompt precedes the next turn
STAMP2='{"session_id":"lc-2","cwd":"/x/payments","hook_event_name":"UserPromptSubmit","source":"user"}'
STAMP1='{"session_id":"lc-1","cwd":"/x/billing","hook_event_name":"UserPromptSubmit","source":"user"}'
sh "$S" set preset basic >/dev/null; printf '%s' "$STAMP2" | sh "$S" stamp >/dev/null; printf '%s' "$LC2" | sh "$S" PermissionRequest >/dev/null
grep -q '^remind_at=$' "$SESSD/lc-2";                        ok $? 0 "basic preset never reminds"
sh "$S" set preset verbose >/dev/null; printf '%s' "$STAMP1" | sh "$S" stamp >/dev/null; printf '%s' "$LC1" | sh "$S" Stop >/dev/null
ra=$(sed -n 's/^remind_at=//p' "$SESSD/lc-1"); since=$(sed -n 's/^since=//p' "$SESSD/lc-1")
[ "$ra" = "$((since + 600))" ];                              ok $? 0 "verbose review reminder is 10 min"
sh "$S" set preset standard >/dev/null; sh "$S" set remind_review off >/dev/null; printf '%s' "$STAMP1" | sh "$S" stamp >/dev/null; printf '%s' "$LC1" | sh "$S" Stop >/dev/null
grep -q '^remind_at=$' "$SESSD/lc-1";                        ok $? 0 "remind_review=off disables review reminders"
sh "$S" set remind_review 5 >/dev/null; printf '%s' "$STAMP1" | sh "$S" stamp >/dev/null; printf '%s' "$LC1" | sh "$S" Stop >/dev/null
ra=$(sed -n 's/^remind_at=//p' "$SESSD/lc-1"); since=$(sed -n 's/^since=//p' "$SESSD/lc-1")
[ "$ra" = "$((since + 300))" ];                              ok $? 0 "remind_review=5 overrides the preset"
sh "$S" unset remind_review >/dev/null
# 7. welcome back: a prompt after a long quiet spell summarises what is waiting; a wake-up does not
printf '%s\n' "$((now - 700))" > "$LCDIR/last_prompt"
out=$(printf '%s' '{"session_id":"lc-9","cwd":"/x/docs","hook_event_name":"UserPromptSubmit","source":"system"}' | sh "$S" stamp)
case "$out" in *welcome_back*) fail=$((fail+1)); echo "FAIL a wake-up must not trigger welcome back: $out" ;; *) pass=$((pass+1)) ;; esac
printf '%s\n' "$((now - 700))" > "$LCDIR/last_prompt"
out=$(printf '%s' '{"session_id":"lc-9","cwd":"/x/docs","hook_event_name":"UserPromptSubmit","source":"user"}' | sh "$S" stamp)
case "$out" in *"while you were away: "*"payments needs your answer"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL welcome back summary: $out" ;; esac
[ "$(cat "$LCDIR/last_prompt")" != "$((now - 700))" ];        ok $? 0 "a real prompt refreshes last_prompt"
out=$(printf '%s' '{"session_id":"lc-9","cwd":"/x/docs","source":"user"}' | sh "$S" stamp)
case "$out" in *welcome_back*) fail=$((fail+1)); echo "FAIL welcome back must not repeat right away: $out" ;; *) pass=$((pass+1)) ;; esac
# 8. the Remind / WelcomeBack events respect the usual gates (mute)
sh "$S" mute >/dev/null
out=$(printf '%s' '{"session_id":"lc-2","message":"payments still needs your answer, 3 minutes"}' | sh "$S" Remind)
case "$out" in SKIP*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL Remind must honour mute: $out" ;; esac
sh "$S" unmute >/dev/null
# 9. board vocabulary
out=$(sh "$S" sessions --plain)
printf '%s' "$out" | grep -q 'payments.*NEEDS ANSWER';        ok $? 0 "board: NEEDS ANSWER"
printf '%s' "$out" | grep -q 'migration.*NEEDS ACTION';       ok $? 0 "board: NEEDS ACTION"
printf '%s' "$out" | grep -q 'needs your action';             ok $? 0 "board legend names the three verbs"
[ "$(sh "$S" sessions --keys --plain | grep 'reviewed = a key' | awk '{print length}')" -le 80 ]; ok $? 0 "board note about keypresses fits 80 columns"
sh "$S" events | grep -q '^  Remind';                         ok $? 0 "events table lists Remind"
# 10. answering the dialog. A permission prompt / AskUserQuestion answer fires no
# UserPromptSubmit; PostToolUse (our `resume`) is the signal that the tool you were asked
# about has run. Regression: the 3-minute "still needs your answer" spoke over a turn
# that had been answered within seconds and was simply still working.
RS2='{"session_id":"lc-2","cwd":"/x/payments","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"git push"},"tool_response":{"stdout":"ok"}}'
printf '%s' "$STAMP2" | sh "$S" stamp >/dev/null; printf '%s' "$LC2" | sh "$S" PermissionRequest >/dev/null
grep -q '^status=blocked' "$SESSD/lc-2";                     ok $? 0 "answer: prompt -> needs your answer"
now=$(date +%s); sed "s/^since=.*/since=$((now - 20))/" "$SESSD/lc-2" > "$SESSD/lc-2.tmp" && mv "$SESSD/lc-2.tmp" "$SESSD/lc-2"
rm -f "$LCDIR/last_prompt"
out=$(printf '%s' "$RS2" | sh "$S" resume)
case "$out" in *"resume: lc-2 answered"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL resume on a blocked row must report it: $out" ;; esac
grep -q '^status=working' "$SESSD/lc-2";                     ok $? 0 "answer: the tool ran -> working"
[ "$(sed -n 's/^since=//p' "$SESSD/lc-2")" -ge "$now" ];     ok $? 0 "answer: since moves (the turn's reminder watcher exits)"
grep -q '^remind_at=$' "$SESSD/lc-2";                        ok $? 0 "answer: the answer reminders are cancelled"
grep -q '^reminded=0' "$SESSD/lc-2";                         ok $? 0 "answer: the reminder counter is reset"
grep -q '^note=$' "$SESSD/lc-2";                             ok $? 0 "answer: the waiting note is cleared"
[ "$(cat "$LCDIR/last_prompt" 2>/dev/null)" -ge "$now" ];    ok $? 0 "answer: counts as you being present (remind_pause)"
out=$(sh "$S" tick lc-2); case "$out" in *SPEAK*) fail=$((fail+1)); echo "FAIL no reminder may follow an answered prompt: $out" ;; *) pass=$((pass+1)) ;; esac
sh "$S" sessions --plain | grep 'payments' | grep -q 'NEEDS ANSWER' && { fail=$((fail+1)); echo "FAIL board still shows NEEDS ANSWER after the answer"; } || pass=$((pass+1))
# a second prompt in the same turn starts its own 3-minute clock (since used to be inherited)
sed "s/^since=.*/since=$((now - 60))/" "$SESSD/lc-2" > "$SESSD/lc-2.tmp" && mv "$SESSD/lc-2.tmp" "$SESSD/lc-2"
printf '%s' "$LC2" | sh "$S" PermissionRequest >/dev/null
ra=$(sed -n 's/^remind_at=//p' "$SESSD/lc-2"); since=$(sed -n 's/^since=//p' "$SESSD/lc-2")
[ "$since" -ge "$now" ] && [ "$ra" = "$((since + 180))" ];   ok $? 0 "answer: a second prompt in the same turn re-arms from its own time"
printf '%s' "$RS2" | sh "$S" resume >/dev/null
# not blocked -> untouched: a READY row keeps its review lifecycle, a working row stays as it is
printf '%s' "$STAMP1" | sh "$S" stamp >/dev/null; printf '%s' "$LC1" | sh "$S" Stop >/dev/null
cp "$SESSD/lc-1" "$SESSD/lc-1.before"
out=$(printf '%s' '{"session_id":"lc-1","cwd":"/x/billing","hook_event_name":"PostToolUse","tool_name":"Read"}' | sh "$S" resume)
[ -z "$out" ] && cmp -s "$SESSD/lc-1" "$SESSD/lc-1.before";  ok $? 0 "resume leaves a READY row alone (review lifecycle untouched)"
rm -f "$SESSD/lc-1.before"
out=$(printf '%s' '{"session_id":"lc-none","cwd":"/x/new","hook_event_name":"PostToolUse","tool_name":"Read"}' | sh "$S" resume)
[ -z "$out" ] && [ ! -e "$SESSD/lc-none" ];                  ok $? 0 "resume never creates a row"
out=$(printf '%s' '{"hook_event_name":"PostToolUse","tool_name":"Read"}' | sh "$S" resume)
[ "$?" = 0 ] && [ -z "$out" ];                               ok $? 0 "resume without a session id exits quietly"
grep -q '"PostToolUse"' "$here/../hooks/hooks.json" && grep '"PostToolUse"' -A1 "$here/../hooks/hooks.json" | grep -q 'iriscale-voice\\" resume'
ok $? 0 "hooks.json wires PostToolUse to resume"
sh "$S" events | grep -q '^  resume';                         ok $? 0 "events table lists resume"
rm -f "$LCDIR/last_prompt"; sh "$S" set repeat_cooldown 0 >/dev/null

# 10. status names the review window; a welcome-back line reaches the speaker with its text
sh "$S" status | grep -q 'review:.*marks it reviewed';         ok $? 0 "status explains the review window"
sh "$S" sessions --keys --plain | grep -q 'within 60s of finishing'; ok $? 0 "board footer states the window"
printf 'agent=claude\nname=wb_pending\nstatus=blocked\nsince=%s\nupdated=%s\npid=\ncwd=/x\nsaid=\nnote=\nreminded=0\nremind_at=\n' "$now" "$now" > "$SESSD/wb-1"
printf '%s\n' "$((now - 700))" > "$LCDIR/last_prompt"
: > "$CLAUDE_CONFIG_DIR/iriscale-voice.log"
printf '%s' '{"session_id":"wb-2","cwd":"/x/docs","hook_event_name":"UserPromptSubmit","source":"user"}' | IRISCALE_VOICE_DEBUG= PATH="$SHIM:$PATH" sh "$S" stamp >/dev/null 2>&1
i=0; while [ $i -lt 30 ] && ! grep -q 'WelcomeBack.while you were away' "$CLAUDE_CONFIG_DIR/iriscale-voice.log" 2>/dev/null; do sleep 1; i=$((i+1)); done   # detached; slow under load
grep -q 'WelcomeBack.while you were away: .*wb pending needs your answer' "$CLAUDE_CONFIG_DIR/iriscale-voice.log"; ok $? 0 "welcome-back line carries its text (stdin was /dev/null before 0.1.27)"
rm -f "$SESSD/wb-1" "$LCDIR/last_prompt"
# 11. review-window: the plugin sets Claude Code's idle window for the user (no hand-editing JSON)
RWS="$CLAUDE_CONFIG_DIR/settings.json"; rm -f "$RWS" "$RWS".iriscale-backup-*
rwvalid() { if command -v node >/dev/null 2>&1; then S2="$1" node -e 'JSON.parse(require("fs").readFileSync(process.env.S2,"utf8"))' 2>/dev/null; else return 0; fi; }
sh "$S" review-window 10 >/dev/null;                            ok $? 0 "review-window 10 with no settings.json"
grep -q '"messageIdleNotifThresholdMs": 600000' "$RWS";          ok $? 0 "  creates settings.json with the value"
sh "$S" sessions --keys --plain | grep -q 'within 10m of finishing'; ok $? 0 "  the board footer now says 10m"
RWFIX='{\n  "model": "opus",\n  "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "echo hi" } ] } ] },\n  "permissions": { "allow": [ "Bash(ls *)" ] }\n}\n'
printf "$RWFIX" > "$RWS"
sh "$S" review-window 10 >/dev/null;                            ok $? 0 "review-window 10 over an existing settings.json"
grep -q '"messageIdleNotifThresholdMs": 600000' "$RWS";          ok $? 0 "  adds the key"
grep -q '"model": "opus"' "$RWS";                                ok $? 0 "  keeps the other keys"
grep -q '"Bash(ls \*)"' "$RWS";                                  ok $? 0 "  keeps nested values"
[ "$(ls "$RWS".iriscale-backup-* 2>/dev/null | wc -l)" -ge 1 ];   ok $? 0 "  backs the file up first"
rwvalid "$RWS";                                                  ok $? 0 "  result is valid JSON"
sh "$S" review-window 5 >/dev/null; grep -q '"messageIdleNotifThresholdMs": 300000' "$RWS"; ok $? 0 "review-window 5 replaces the value"
[ "$(grep -c messageIdleNotifThresholdMs "$RWS")" = 1 ];          ok $? 0 "  exactly one key"
sh "$S" review-window default >/dev/null; grep -q '"messageIdleNotifThresholdMs": 60000' "$RWS"; ok $? 0 "review-window default -> 60000"
sh "$S" review-window abc >/dev/null 2>&1;                       ok $? 2 "review-window rejects a non-number (exit 2)"
sh "$S" review-window 0 >/dev/null 2>&1;                         ok $? 2 "review-window rejects 0"
sh "$S" review-window | grep -q 'review-window 10';              ok $? 0 "review-window with no argument recommends 10 at the default"
sh "$S" status | grep -q 'review-window 10';                     ok $? 0 "status recommends review-window 10 at the default"
# the text-edit path (machines with neither node nor python3) must give the same, valid result
printf "$RWFIX" > "$RWS"
IRISCALE_VOICE_NO_JSON_TOOLS=1 sh "$S" review-window 10 >/dev/null; ok $? 0 "text edit: adds the key to a pretty file"
grep -q '"messageIdleNotifThresholdMs": 600000' "$RWS" && grep -q '"model": "opus"' "$RWS" && rwvalid "$RWS"; ok $? 0 "  key added, others kept, valid JSON"
IRISCALE_VOICE_NO_JSON_TOOLS=1 sh "$S" review-window 5 >/dev/null; grep -q '"messageIdleNotifThresholdMs": 300000' "$RWS" && [ "$(grep -c messageIdleNotifThresholdMs "$RWS")" = 1 ] && rwvalid "$RWS"; ok $? 0 "text edit: replaces an existing key"
printf '{}\n' > "$RWS"; IRISCALE_VOICE_NO_JSON_TOOLS=1 sh "$S" review-window 10 >/dev/null; grep -q '"messageIdleNotifThresholdMs": 600000' "$RWS" && rwvalid "$RWS"; ok $? 0 "text edit: handles an empty object"
printf '{"a":1}' > "$RWS"; IRISCALE_VOICE_NO_JSON_TOOLS=1 sh "$S" review-window 10 >/dev/null; rwvalid "$RWS"; ok $? 0 "text edit: handles a compact object"
rm -f "$RWS" "$RWS".iriscale-backup-*

echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
