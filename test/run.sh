#!/bin/sh
# Fires every event through every preset in debug mode (never speaks) and checks
# the decisions. Run from anywhere:  sh test/run.sh
# Uses a throwaway config so it never touches ~/.claude/iriscale-voice.conf.

here=$(cd "$(dirname "$0")" && pwd)
S="$here/../bin/notify.sh"
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

for preset in off basic standard verbose; do
    sh "$S" set preset $preset >/dev/null
    for ev in Stop StopFailure PermissionRequest idle_prompt agent_completed SubagentStop SessionEnd; do
        case " $(sh "$S" status | sed -n 's/.*speaks on: //p') " in
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

echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
