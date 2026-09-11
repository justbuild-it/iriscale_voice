#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
# Git Bash may expose /tmp through a different physical path. The launcher
# deliberately resolves its executable with pwd -P; compare the same form.
scratch=$(CDPATH= cd -P -- "$scratch" && pwd -P)
export CLAUDE_CONFIG_DIR="$scratch/config" TMPDIR="$scratch/tmp" CODEX_HOME="$scratch/codex"
mkdir -p "$CLAUDE_CONFIG_DIR" "$TMPDIR" "$CODEX_HOME"
trap 'rm -rf "$scratch"' EXIT
export IRISCALE_VOICE_DEBUG=1
S="$root/bin/iriscale-voice"
fail=0
check() { if "$@"; then :; else echo "FAIL: $*"; fail=$((fail+1)); fi; }
for command in 'curl -H \"x-api-key: auditsecret123\" https://x' 'echo \"sk-live-auditsecret123\"' 'echo API_KEY=auditsecret123'; do
    out=$(printf '{"session_id":"privacy","cwd":"/x/api","tool_name":"Bash","tool_input":{"command":"%s"}}' "$command" | sh "$S" PermissionRequest)
    case $out in *auditsecret123*) echo 'FAIL: credential reached announcement'; fail=$((fail+1));; esac
done
printf '%s' '{"session_id":"repeat","cwd":"/x/api"}' | sh "$S" PermissionRequest >/dev/null
before=$(sed -n 's/^remind_at=//p' "$CLAUDE_CONFIG_DIR/iriscale-voice-sessions/repeat")
sleep 2
printf '%s' '{"session_id":"repeat","cwd":"/x/api"}' | sh "$S" PermissionRequest >/dev/null
check grep -q '^remind_at=[0-9]' "$CLAUDE_CONFIG_DIR/iriscale-voice-sessions/repeat"
check test "$before" = "$(sed -n 's/^remind_at=//p' "$CLAUDE_CONFIG_DIR/iriscale-voice-sessions/repeat")"
printf '%s' '{"session_id":"repeat","cwd":"/x/api"}' | sh "$S" resume >/dev/null
check grep -q '^status=working' "$CLAUDE_CONFIG_DIR/iriscale-voice-sessions/repeat"
printf '%s' '{"session_id":"repeat","cwd":"/x/api"}' | sh "$S" PermissionRequest >/dev/null
check grep -q '^remind_at=[0-9]' "$CLAUDE_CONFIG_DIR/iriscale-voice-sessions/repeat"

mkdir -p "$scratch/stubs"
printf '#!/bin/sh\necho Darwin\n' > "$scratch/stubs/uname"
cat > "$scratch/stubs/say" <<'SAY'
#!/bin/sh
if [ "${1:-}" = -v ] && [ "${2:-}" = '?' ]; then echo 'Samantha en_US hello'; exit 0; fi
exit 42
SAY
chmod +x "$scratch/stubs/"*
if OS= IRISCALE_VOICE_DEBUG= PATH="$scratch/stubs:$PATH" sh "$S" test > "$scratch/out" 2>&1; then
    echo 'FAIL: failed Mac speech reported success'; fail=$((fail+1))
fi
if OS= IRISCALE_VOICE_DEBUG= PATH="$scratch/stubs:$PATH" sh "$S" speaker Samantha > "$scratch/out" 2>&1; then
    echo 'FAIL: failed Mac sample reported success'; fail=$((fail+1))
fi
OS= PATH="$scratch/stubs:$PATH" sh "$S" sessions --keys --plain > "$scratch/board"
check grep -q 'focusing is unavailable on macOS' "$scratch/board"

export AUDIT_ARGS="$scratch/args" AUDIT_CODE="$scratch/code"
cat > "$scratch/stubs/osascript" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" > "$AUDIT_ARGS"
cat > "$AUDIT_CODE"
exit "${AUDIT_EXIT:-0}"
STUB
chmod +x "$scratch/stubs/osascript"
mkdir "$scratch/O'Neil"
cp "$S" "$scratch/O'Neil/iriscale-voice"
(cd "$scratch"; OS= PATH="$scratch/stubs:$PATH" sh "O'Neil/iriscale-voice" board --open > "$scratch/launch")
check grep -Fq "$scratch/O'Neil/iriscale-voice" "$AUDIT_ARGS"
check grep -q 'quoted form' "$AUDIT_CODE"
if OS= AUDIT_EXIT=42 PATH="$scratch/stubs:$PATH" sh "$S" board --open > "$scratch/out" 2>&1; then
    echo 'FAIL: failed Terminal launch reported success'; fail=$((fail+1))
fi

# A pre-existing shared temp path must not be touched. Runtime files are user-private.
mkdir -p "$TMPDIR/iriscale-voice"
echo sentinel > "$TMPDIR/iriscale-voice/last_prompt"
sh "$S" --version >/dev/null
check test "$(cat "$TMPDIR/iriscale-voice/last_prompt")" = sentinel
check test -d "$CLAUDE_CONFIG_DIR/iriscale-voice-runtime"
shell=$(command -v sh)
printf '%s' '{"session_id":"pathless","cwd":"/x/api"}' | PATH= "$shell" "$S" Stop >/dev/null
mkdir "$scratch/linked-config" "$scratch/target"
ln -s "$scratch/target" "$scratch/linked-config/iriscale-voice-runtime"
if [ -L "$scratch/linked-config/iriscale-voice-runtime" ]; then
    if CLAUDE_CONFIG_DIR="$scratch/linked-config" sh "$S" --version > "$scratch/out" 2>&1; then
        echo 'FAIL: runtime symlink accepted'; fail=$((fail+1))
    fi
else echo 'skip: filesystem does not create Unix symlinks'; fi
echo "audit runtime: $fail failed"
[ "$fail" -eq 0 ]
