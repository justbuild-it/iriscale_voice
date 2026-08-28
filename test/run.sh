#!/bin/sh
# Fires every event through every preset in debug mode (never speaks) and checks
# the decisions. Run from anywhere:  sh test/run.sh
# Uses a throwaway config so it never touches ~/.claude/iriscale-voice.conf.

here=$(cd "$(dirname "$0")" && pwd)
S="$here/../bin/iriscale-voice"
export IRISCALE_VOICE_DEBUG=1
export CLAUDE_CONFIG_DIR="${TMPDIR:-/tmp}/iriscale-voice-test-$$"
mkdir -p "$CLAUDE_CONFIG_DIR"
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
IRISCALE_VOICE_OFF=1 expect SKIP idle_prompt
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
sed -i 's/^since=.*/since=123/' "$SESSD/brd-1"
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
printf '%s' "$out" | grep -q 'payments_api.*NEEDS YOU';   ok $? 0 "sessions shows NEEDS YOU"
printf '%s' "$out" | grep -q 'billing_service.*READY';    ok $? 0 "sessions shows READY"
printf '%s' "$out" | grep -q 'data_migration.*ERROR';     ok $? 0 "sessions shows ERROR"
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
# version must agree in script, plugin.json, marketplace.json (release process guard)
v_script=$(sh "$S" --version)
v_plugin=$(grep -o '"version": *"[^"]*"' "$here/../.claude-plugin/plugin.json"      | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
v_market=$(grep -o '"version": *"[^"]*"' "$here/../.claude-plugin/marketplace.json" | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
v_codex=$(grep -o '"version": *"[^"]*"' "$here/../.codex-plugin/plugin.json"       | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
ok "$v_plugin" "$v_script" "plugin.json version == script VERSION"
ok "$v_market" "$v_script" "marketplace.json version == script VERSION"
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

# Non-blocking speech guard: hosts that run hooks synchronously (Codex) must get the
# hook back in well under a second even though speaking takes seconds. Stub every
# speech backend with a 3 s sleep; the script must return without waiting for it.
for spk in powershell.exe say spd-say espeak-ng espeak notify-send; do
    printf '#!/bin/sh\nsleep 3\n' > "$SHIM/$spk"; chmod +x "$SHIM/$spk"
done
t0=$(date +%s)
printf '%s' '{"session_id":"sync-1","cwd":"/x/sync_host"}' | IRISCALE_VOICE_DEBUG= PATH="$SHIM:$PATH" sh "$S" Stop >/dev/null 2>&1
t1=$(date +%s)
if [ $((t1 - t0)) -le 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL hook blocked $((t1 - t0))s on speech - must background the speaker"; fi
sleep 4   # let the stubbed background speaker finish before the trap cleans the shim dir

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

echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
