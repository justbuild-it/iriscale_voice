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
case "$out" in *"api wants to run git push"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL perm phrasing: $out" ;; esac
# failure reason
out=$(printf '%s' '{"session_id":"t","cwd":"/x/api","reason":"rate_limit"}' | sh "$S" StopFailure)
case "$out" in *"stopped: rate limit"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL reason: $out" ;; esac
# duration gate: stamp then immediate Stop => SKIP; StopFailure still SPEAKs
printf '%s' "$P" | sh "$S" stamp
expect SKIP  Stop
expect SPEAK StopFailure
# overrides & gates
sh "$S" set event.SubagentStop on >/dev/null;  expect SPEAK SubagentStop; sh "$S" set event.SubagentStop "" >/dev/null
sh "$S" set quiet_hours 0-23 >/dev/null;       expect SKIP idle_prompt;   sh "$S" set quiet_hours "" >/dev/null
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
ok() { if [ "$1" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $3: got '$1' wanted '$2'"; fi; }
sh "$S" --help >/dev/null 2>&1;            ok $? 0 "--help exit"
sh "$S" --help | grep '^USAGE' >/dev/null;         ok $? 0 "--help has USAGE"
sh "$S" -h    | grep 'config list' >/dev/null;     ok $? 0 "-h lists config"
sh "$S" --bogus >/dev/null 2>&1;           ok $? 2 "unknown option exits 2"
sh "$S" config nope >/dev/null 2>&1;       ok $? 2 "unknown config sub exits 2"
sh "$S" config set rate 3 >/dev/null;      ok "$(sh "$S" config get rate)" 3 "config set/get"
sh "$S" config unset rate >/dev/null;      ok "$(sh "$S" config get rate)" "(unset - using default)" "config unset"
ok "$(sh "$S" config path)" "$CLAUDE_CONFIG_DIR/iriscale-voice.conf" "config path"
sh "$S" config list | grep '^repeat_cooldown' >/dev/null;  ok $? 0 "config list has repeat_cooldown"
sh "$S" events | grep 'PermissionRequest' >/dev/null;      ok $? 0 "events lists PermissionRequest"
sh "$S" presets | grep '^  verbose' >/dev/null;            ok $? 0 "presets lists verbose"
# version must agree in script, plugin.json, marketplace.json (release process guard)
v_script=$(sh "$S" --version)
v_plugin=$(grep -o '"version": *"[^"]*"' "$here/../.claude-plugin/plugin.json"      | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
v_market=$(grep -o '"version": *"[^"]*"' "$here/../.claude-plugin/marketplace.json" | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
ok "$v_plugin" "$v_script" "plugin.json version == script VERSION"
ok "$v_market" "$v_script" "marketplace.json version == script VERSION"
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

echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
