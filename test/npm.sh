#!/bin/sh
# The npm installer: what it writes into a throwaway ~/.codex, that it is idempotent,
# that it refuses to touch a broken hooks.json, and that `uninstall codex` puts every
# file back. Never touches your real Codex configuration. Run: sh test/npm.sh

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

command -v node >/dev/null 2>&1 || { echo "npm installer: SKIP (node not installed)"; exit 0; }

tmp=${TMPDIR:-/tmp}; tmp=${tmp%/}      # macOS TMPDIR ends in / and node normalizes //
SANDBOX="$tmp/iriscale-voice-npm-test-$$"
# Under Git Bash only PATH/HOME/TMP-like variables get MSYS->Win32 conversion; every other
# path we hand to node arrives as a raw POSIX string and resolves against the cwd drive.
# The mirror-image trap is in ARGUMENTS: MSYS rewrites anything in an argv that looks like
# an absolute POSIX path, so a bare "/hooks.json" inside a `node -e` script becomes
# "C:/Program Files/Git/hooks.json" and the concatenation silently reads the wrong file.
# Every node -e below therefore builds paths with path.join and no leading-slash literal.
# Normalising $SANDBOX once fixes every variable derived from it. WINDOWS also gates the
# PATH tests below, which on Windows would edit the REAL user PATH.
WINDOWS=0
case $(uname -s 2>/dev/null) in
    MINGW*|MSYS*|CYGWIN*) WINDOWS=1; SANDBOX=$(cygpath -m "$SANDBOX") ;;
esac
export HOME="$SANDBOX/home"
export CODEX_HOME="$SANDBOX/home/.codex"
export IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt/iriscale-voice"
mkdir -p "$CODEX_HOME"
trap 'rm -rf "$SANDBOX"' EXIT

CLI="node $root/npm/cli.js"
CONF="$CODEX_HOME/config.toml"
HOOKS="$CODEX_HOME/hooks.json"
SCRIPT="$IRISCALE_VOICE_INSTALL_ROOT/bin/iriscale-voice"
fail=0; pass=0

ok()      { if [ "$1" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $3: got '$1' wanted '$2'"; fi; }
yes()     { if eval "$1"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $2"; fi; }
# -e/-- so a pattern beginning with a dash is a pattern, not an option (and grep can
# never end up reading stdin, which hangs the whole suite).
has()     { if grep -q -e "$1" -- "$2" 2>/dev/null; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $3"; fi; }
hasnt()   { if grep -q -e "$1" -- "$2" 2>/dev/null; then fail=$((fail+1)); echo "FAIL $3"; else pass=$((pass+1)); fi; }
exists()  { if [ -e "$1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $2"; fi; }
gone()    { if [ -e "$1" ]; then fail=$((fail+1)); echo "FAIL $2"; else pass=$((pass+1)); fi; }

# The hook probes below deliberately repeat a line; $TMPDIR state outlives the sandbox,
# so turn the 60s repeat cooldown off for them (test/run.sh does the same).
sh "$root/bin/iriscale-voice" set repeat_cooldown 0 >/dev/null 2>&1

echo "npm installer:"

# --- dry run: printing the plan must not write anything --------------------------
plan=$($CLI install codex 2>&1)
gone "$CONF"   "install codex without --apply wrote config.toml"
gone "$SCRIPT" "install codex without --apply installed files"
case $plan in *"$SCRIPT"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL the plan names the stable script path" ;; esac
case $plan in *notify*)    pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL the plan prints the notify line" ;; esac
# nothing is installed yet, so the plan has to say how to put the script there
case $plan in *"chmod 755"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL the plan explains the manual copy" ;; esac

# --- a Codex config that already has settings we must not lose -------------------
cat > "$CONF" <<'EOF'
model = "gpt-5-codex"

[tui]
theme = "dark"
EOF
cat > "$HOOKS" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "echo hi", "timeout": 5 } ] } ] } }
EOF

$CLI install codex --apply --skip-path >/dev/null 2>&1
ok $? 0 "install codex --apply exit status"

exists "$SCRIPT" "the stable copy of bin/iriscale-voice"
exists "$CODEX_HOME/skills/iriscale-voice/SKILL.md" "the Codex skill"
exists "$CODEX_HOME/skills/iriscale-voice/agents/openai.yaml" "the skill agent card"
exists "$IRISCALE_VOICE_INSTALL_ROOT/install.json" "the install marker"
case $(uname -s 2>/dev/null) in           # no exec bit on Windows filesystems
    Darwin|Linux) yes '[ -x "$SCRIPT" ]' "the installed script is executable (notify execs it directly)" ;;
esac

# notify must be the FIRST line: it is a top-level key and TOML puts it inside the
# preceding [table] otherwise - the bug that silently disables notify.
ok "$(head -1 "$CONF" | cut -c1-6)" "notify" "notify is the first line of config.toml"
has 'iriscale-voice' "$CONF" "notify points at iriscale-voice"
has 'model = "gpt-5-codex"' "$CONF" "unrelated config.toml settings survive"
has 'theme = "dark"' "$CONF" "unrelated config.toml tables survive"
ok "$(grep -c '^notify' "$CONF")" "1" "exactly one notify line"

has '"UserPromptSubmit"' "$HOOKS" "UserPromptSubmit hook written"
has '"PermissionRequest"' "$HOOKS" "PermissionRequest hook written"
has '"SessionStart"' "$HOOKS" "unrelated hooks survive"
hasnt '"async"' "$HOOKS" "no async hooks (Codex 0.147 skips them)"
ok "$(grep -c '"command":' "$HOOKS")" "3" "each hook has a command field"
# 2>&1, not 2>/dev/null: a swallowed error here says only "got 1 wanted 0", which is
# the one thing a JSON failure must never be. Show what node actually objected to.
jsonerr=$(node -e 'JSON.parse(require("fs").readFileSync(require("path").join(process.env.CODEX_HOME,"hooks.json"),"utf8"))' 2>&1); jsonst=$?
ok "$jsonst" 0 "hooks.json is still valid JSON"
[ "$jsonst" = 0 ] || echo "     node: $jsonerr"

# The sh script's own diagnostic has to agree with what the installer wrote.
sh "$root/bin/iriscale-voice" doctor codex >/dev/null 2>&1
ok $? 0 "doctor codex passes on the generated configuration"

# --- idempotent: a second run must not duplicate anything -------------------------
$CLI install codex --apply --skip-path >/dev/null 2>&1
ok "$(grep -c '^notify' "$CONF")" "1" "re-install leaves exactly one notify line"
ok "$(grep -c '"UserPromptSubmit"' "$HOOKS")" "1" "re-install leaves one UserPromptSubmit hook"
yes '[ -n "$(ls "$CODEX_HOME"/config.toml.iriscale-backup-* 2>/dev/null)" ]' "an edited file is backed up"

# --- PATH: skipped when already installed, but NOT for npx's temporary shim -------
# npx puts ~/.npm/_npx/<hash>/node_modules/.bin on PATH while it runs. Treating that as
# "already installed" would mean `npx ... install codex --apply` never puts the command
# on PATH at all.
if [ "$WINDOWS" = 0 ]; then      # on Windows this path edits the REAL user PATH
    mkdir -p "$SANDBOX/_npx/abc/node_modules/.bin" "$SANDBOX/realbin"
    : > "$SANDBOX/_npx/abc/node_modules/.bin/iriscale-voice"; chmod +x "$SANDBOX/_npx/abc/node_modules/.bin/iriscale-voice"
    : > "$SANDBOX/realbin/iriscale-voice";                    chmod +x "$SANDBOX/realbin/iriscale-voice"
    rm -rf "$HOME/.local/bin"
    PATH="$SANDBOX/_npx/abc/node_modules/.bin:$PATH" $CLI install codex --apply >/dev/null 2>&1
    exists "$HOME/.local/bin/iriscale-voice" "a durable symlink despite npx's shim on PATH"
    rm -rf "$HOME/.local/bin"
    PATH="$SANDBOX/realbin:$PATH" $CLI install codex --apply >/dev/null 2>&1
    gone "$HOME/.local/bin/iriscale-voice" "no second entry when iriscale-voice is really on PATH"
fi

# --- a broken hooks.json is refused before anything is written --------------------
cp "$CONF" "$SANDBOX/config.before"
echo 'not json {' > "$HOOKS"
$CLI install codex --apply --skip-path >/dev/null 2>&1
ok $? 1 "install refuses a hooks.json that does not parse"
yes 'cmp -s "$CONF" "$SANDBOX/config.before"' "the refused install changed nothing else"
ok "$(cat "$HOOKS")" "not json {" "the refused install left hooks.json alone"

# --- uninstall puts it back -------------------------------------------------------
cat > "$HOOKS" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "echo hi", "timeout": 5 } ] } ] } }
EOF
$CLI install codex --apply --skip-path >/dev/null 2>&1
$CLI uninstall codex --skip-path >/dev/null 2>&1
ok $? 0 "uninstall codex exit status"
hasnt '^notify' "$CONF" "notify removed"
has 'model = "gpt-5-codex"' "$CONF" "uninstall keeps unrelated settings"
hasnt '"UserPromptSubmit"' "$HOOKS" "our hooks removed"
has '"SessionStart"' "$HOOKS" "uninstall keeps unrelated hooks"
gone "$CODEX_HOME/skills/iriscale-voice" "the skill directory"
gone "$IRISCALE_VOICE_INSTALL_ROOT" "the install directory"

# --- an install into a machine with no Codex config gives every file back ---------
# The installer creates ~/.codex, config.toml and hooks.json when they are missing.
# Uninstall must not leave an empty shell of each behind.
FRESH="$SANDBOX/fresh"
CODEX_HOME="$FRESH/.codex" IRISCALE_VOICE_INSTALL_ROOT="$FRESH/opt/iriscale-voice" $CLI install codex --apply --skip-path >/dev/null 2>&1
exists "$FRESH/.codex/config.toml" "a fresh install creates config.toml"
CODEX_HOME="$FRESH/.codex" IRISCALE_VOICE_INSTALL_ROOT="$FRESH/opt/iriscale-voice" $CLI uninstall codex --skip-path >/dev/null 2>&1
gone "$FRESH/.codex/config.toml" "config.toml we created is removed again"
gone "$FRESH/.codex/hooks.json"  "hooks.json we created is removed again"
gone "$FRESH/.codex/skills"      "the skills directory we created is removed again"
gone "$FRESH/.codex"             "the .codex directory we created is removed again"
ok "$(ls "$FRESH/.codex"/*.iriscale-backup-* 2>/dev/null | wc -l | tr -d '[:space:]')" "0" \
   "uninstall leaves no backup of a file it deleted"

# ...but a file that was already there, with the user's settings in it, stays.
KEEP="$SANDBOX/keep"; mkdir -p "$KEEP/.codex"
printf 'model = "gpt-5-codex"\n' > "$KEEP/.codex/config.toml"
CODEX_HOME="$KEEP/.codex" IRISCALE_VOICE_INSTALL_ROOT="$KEEP/opt/iriscale-voice" $CLI install codex --apply --skip-path >/dev/null 2>&1
CODEX_HOME="$KEEP/.codex" IRISCALE_VOICE_INSTALL_ROOT="$KEEP/opt/iriscale-voice" $CLI uninstall codex --skip-path >/dev/null 2>&1
exists "$KEEP/.codex/config.toml" "a config.toml that was already there survives uninstall"
has 'model = "gpt-5-codex"' "$KEEP/.codex/config.toml" "and keeps the settings in it"

# --- repeated installs must not pile up identical backups ------------------------
REP="$SANDBOX/repeat"; mkdir -p "$REP/.codex"
printf 'model = "gpt-5-codex"\n' > "$REP/.codex/config.toml"
backups() { ls "$REP/.codex"/config.toml.iriscale-backup-* 2>/dev/null | wc -l | tr -d '[:space:]'; }
reinstall() { CODEX_HOME="$REP/.codex" IRISCALE_VOICE_INSTALL_ROOT="$REP/opt/iriscale-voice" \
              $CLI install codex --apply --skip-path >/dev/null 2>&1; }
reinstall; reinstall; n2=$(backups)
reinstall;              n3=$(backups)
# Once the file stops changing, re-running must stop producing backups of it.
ok "$n3" "$n2" "a repeated install adds no further backup"
dupes=0
for a in "$REP/.codex"/config.toml.iriscale-backup-*; do
    for b in "$REP/.codex"/config.toml.iriscale-backup-*; do
        [ "$a" = "$b" ] && continue
        cmp -s "$a" "$b" && dupes=$((dupes+1))
    done
done
ok "$dupes" "0" "no two backups hold the same content"


# ================= Claude Code (the npx route, not the plugin) ===================
CDIR="$SANDBOX/claude"; mkdir -p "$CDIR"
CLAUDE_CONFIG_DIR="$CDIR" sh "$root/bin/iriscale-voice" set repeat_cooldown 0 >/dev/null 2>&1
CROOT="$SANDBOX/opt-claude/iriscale-voice"
SET="$CDIR/settings.json"
CSCRIPT="$CROOT/bin/iriscale-voice"
claude_cli() { CLAUDE_CONFIG_DIR="$CDIR" IRISCALE_VOICE_INSTALL_ROOT="$CROOT" $CLI "$@"; }
jq_node() { node -e "$1" 2>/dev/null; }

# settings the user already had, plus a Stop hook of their own that must survive
cat > "$SET" <<'EOF'
{
  "model": "opus",
  "permissions": { "allow": ["Bash(ls *)"] },
  "hooks": {
    "Stop": [ { "hooks": [ { "type": "command", "command": "echo my-own-hook" } ] } ]
  }
}
EOF

claude_cli install claude --apply --skip-path >/dev/null 2>&1
ok $? 0 "install claude --apply exit status"
has '"messageIdleNotifThresholdMs": 600000' "$CDIR/settings.json" "install claude sets the 10-minute review window"
exists "$CSCRIPT"                              "the stable script for Claude Code"
exists "$CDIR/skills/iriscale-voice/SKILL.md"  "the Claude Code skill"
exists "$CDIR/commands/iriscale-voice-status.md" "the flat, prefixed slash commands"
ok "$(ls "$CDIR/commands"/iriscale-voice-*.md 2>/dev/null | wc -l | tr -d '[:space:]')" \
   "$(ls "$root/commands"/*.md | wc -l | tr -d '[:space:]')" "every command is installed"
# a command we shipped once and renamed must not linger in the picker (the `voice` command
# became `speaker`). A user's own file sharing the prefix, and any unprefixed file, stay put.
printf -- '---\ndescription: old\n---\nRun: sh "/x/iriscale-voice" oldthing\n' > "$CDIR/commands/iriscale-voice-oldthing.md"
printf -- '---\ndescription: mine\n---\nmy own notes\n' > "$CDIR/commands/iriscale-voice-mine.md"
printf -- '---\ndescription: mine\n---\nmy own notes\n' > "$CDIR/commands/notes.md"
claude_cli install claude --apply --skip-path >/dev/null 2>&1
gone "$CDIR/commands/iriscale-voice-oldthing.md" "a renamed command is pruned on install"
exists "$CDIR/commands/iriscale-voice-mine.md"   "a user's own prefixed file is left alone"
exists "$CDIR/commands/notes.md"                 "an unprefixed file is left alone"
exists "$CDIR/commands/iriscale-voice-status.md" "the shipping commands survive the prune"
# ~/.claude/commands takes flat files only - a subdirectory there is NOT a namespace
gone "$CDIR/commands/iriscale-voice" "no subdirectory (Claude Code would not find it)"

# ${CLAUDE_PLUGIN_ROOT} only exists inside the plugin system; outside it must be resolved
hasnt 'CLAUDE_PLUGIN_ROOT' "$CDIR/commands/iriscale-voice-status.md" "commands have no unresolved plugin root"
has "$CROOT" "$CDIR/commands/iriscale-voice-status.md" "commands point at the stable script"
# a command that tells the user to run /iriscale-voice:speaker must respell it: the
# namespaced form does not exist outside the plugin, so the example would be dead.
has '/iriscale-voice-speaker "Samantha"' "$CDIR/commands/iriscale-voice-speaker.md" \
    "the example command is respelled flat"
hasnt '/iriscale-voice:' "$CDIR/commands/iriscale-voice-speaker.md" \
    "no plugin-namespaced command spelling survives the install"
hasnt 'CLAUDE_PLUGIN_ROOT' "$SET" "settings.json has no unresolved plugin root"

ok "$(jq_node "const d=require('$SET');console.log(Object.keys(d.hooks).length)")" "8" \
   "all eight hook events are configured"
ok "$(jq_node "const d=require('$SET');console.log(d.model)")" "opus" "unrelated settings survive"
ok "$(jq_node "const d=require('$SET');console.log(d.permissions.allow[0])")" "Bash(ls *)" "permissions survive"
ok "$(jq_node "const d=require('$SET');console.log(d.hooks.Stop.filter(g=>JSON.stringify(g).includes('my-own-hook')).length)")" \
   "1" "the user's own Stop hook survives"
ok "$(jq_node "const d=require('$SET');console.log(d.hooks.Stop.length)")" "2" "ours is appended beside it"

# idempotent
claude_cli install claude --apply --skip-path >/dev/null 2>&1
ok "$(jq_node "const d=require('$SET');console.log(d.hooks.Stop.length)")" "2" \
   "a second install does not duplicate our hook"
ok "$(jq_node "const d=require('$SET');console.log(d.hooks.Notification.filter(g=>JSON.stringify(g).includes('iriscale')).length)")" \
   "2" "the two Notification matchers are installed once each"

# the generated hook command must actually run and speak
CMD=$(jq_node "const d=require('$SET');console.log(d.hooks.Stop.find(g=>JSON.stringify(g).includes('iriscale')).hooks[0].command)")
out=$(printf '{"session_id":"claude-e2e","cwd":"/home/dev/claude_hook_probe"}' | CLAUDE_CONFIG_DIR="$CDIR" IRISCALE_VOICE_DEBUG=1 sh -c "$CMD" 2>&1)
case $out in SPEAK*done*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL the generated Claude hook speaks: got '$out'" ;; esac

# --- the plugin guard: installing both would speak twice --------------------------
# a marketplace merely being ADDED must not trip the guard - only a real install does
mkdir -p "$CDIR/plugins/marketplaces/iriscale/iriscale-voice"
cp "$SET" "$SANDBOX/settings.before"
claude_cli install claude --apply --skip-path >/dev/null 2>&1
ok $? 0 "an added marketplace alone does not block the install"
mkdir -p "$CDIR/plugins/installed/iriscale-voice/.claude-plugin"
printf '{"name":"iriscale-voice","version":"0.1.23"}\n' > "$CDIR/plugins/installed/iriscale-voice/.claude-plugin/plugin.json"
cp "$SET" "$SANDBOX/settings.before"
claude_cli install claude --apply --skip-path >/dev/null 2>&1
ok $? 1 "install refuses when the Claude Code plugin is present"
yes 'cmp -s "$SET" "$SANDBOX/settings.before"' "the refused install changed nothing"
claude_cli install claude --apply --skip-path --force >/dev/null 2>&1
ok $? 0 "--force installs anyway"
rm -rf "$CDIR/plugins"
# enabledPlugins in settings.json is the authoritative signal
D="$CDIR" node -e 'const fs=require("fs"),p=require("path").join(process.env.D,"settings.json");const d=JSON.parse(fs.readFileSync(p,"utf8"));d.enabledPlugins={"iriscale-voice@iriscale":true};fs.writeFileSync(p,JSON.stringify(d,null,2))'
claude_cli install claude --apply --skip-path >/dev/null 2>&1
ok $? 1 "install refuses when enabledPlugins lists the plugin"
D="$CDIR" node -e 'const fs=require("fs"),p=require("path").join(process.env.D,"settings.json");const d=JSON.parse(fs.readFileSync(p,"utf8"));d.enabledPlugins={"iriscale-voice@iriscale":false};fs.writeFileSync(p,JSON.stringify(d,null,2))'
claude_cli install claude --apply --skip-path >/dev/null 2>&1
ok $? 0 "a DISABLED plugin does not block the install"
D="$CDIR" node -e 'const fs=require("fs"),p=require("path").join(process.env.D,"settings.json");const d=JSON.parse(fs.readFileSync(p,"utf8"));delete d.enabledPlugins;fs.writeFileSync(p,JSON.stringify(d,null,2))' 

# --- one install directory, two agents -------------------------------------------
CODEX2="$SANDBOX/codex2"; mkdir -p "$CODEX2"
CODEX_HOME="$CODEX2" IRISCALE_VOICE_INSTALL_ROOT="$CROOT" $CLI install codex --apply --skip-path >/dev/null 2>&1
ok "$(jq_node "console.log(Object.keys(require('$CROOT/install.json').agents).sort().join(','))")" "claude,codex" \
   "the marker records both agents"
CODEX_HOME="$CODEX2" IRISCALE_VOICE_INSTALL_ROOT="$CROOT" $CLI uninstall codex --skip-path >/dev/null 2>&1
exists "$CSCRIPT" "uninstalling Codex leaves the install Claude Code still uses"
ok "$(jq_node "const d=require('$SET');console.log(d.hooks.Stop.length)")" "2" "and leaves its hooks alone"

# --- uninstall claude -------------------------------------------------------------
claude_cli uninstall claude --skip-path >/dev/null 2>&1
ok $? 0 "uninstall claude exit status"
ok "$(jq_node "const d=require('$SET');console.log(d.hooks.Stop.length)")" "1" "our hook is gone"
ok "$(jq_node "const d=require('$SET');console.log(JSON.stringify(d.hooks.Stop[0]).includes('my-own-hook'))")" "true" \
   "the user's own hook is what remains"
ok "$(jq_node "const d=require('$SET');console.log(d.model)")" "opus" "unrelated settings still survive"
gone "$CDIR/skills/iriscale-voice"   "the Claude Code skill directory"
gone "$CDIR/commands/iriscale-voice-status.md" "the installed commands"
gone "$CDIR/commands/iriscale-voice-oldthing.md" "and any command from an older version"
exists "$CDIR/commands/iriscale-voice-mine.md"   "uninstall still leaves a user's own file"
gone "$CROOT" "the shared install directory goes with the last agent"

# --- Codex: a user's own hook on one of our events must survive too ---------------
OWN="$SANDBOX/own"; mkdir -p "$OWN"
cat > "$OWN/hooks.json" <<'EOF'
{ "hooks": { "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "echo mine", "timeout": 5 } ] } ] } }
EOF
CODEX_HOME="$OWN" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-own/iriscale-voice" $CLI install codex --apply --skip-path >/dev/null 2>&1
ok "$(jq_node "const d=require('$OWN/hooks.json');console.log(d.hooks.UserPromptSubmit.length)")" "2" \
   "Codex keeps the user's own UserPromptSubmit hook"
CODEX_HOME="$OWN" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-own/iriscale-voice" $CLI uninstall codex --skip-path >/dev/null 2>&1
ok "$(jq_node "const d=require('$OWN/hooks.json');console.log(d.hooks.UserPromptSubmit.length)")" "1" \
   "and gives it back untouched on uninstall"


# --- doctor claude ----------------------------------------------------------------
DDIR="$SANDBOX/doc"; DROOT="$SANDBOX/opt-doc/iriscale-voice"
doc_cli() { CLAUDE_CONFIG_DIR="$DDIR" IRISCALE_VOICE_INSTALL_ROOT="$DROOT" $CLI "$@"; }
mkdir -p "$DDIR"
doc_cli doctor claude >/dev/null 2>&1
ok $? 1 "doctor claude fails before anything is installed"
doc_cli install claude --apply --skip-path >/dev/null 2>&1
doc_cli doctor claude >/dev/null 2>&1
ok $? 0 "doctor claude passes on a fresh install"
# Notification carries two of ours under different matchers - that is not a duplicate
doc_cli doctor claude 2>&1 | grep -q 'speak 2 times' && { fail=$((fail+1)); echo "FAIL doctor claude miscounts the two Notification matchers"; } || pass=$((pass+1))
# ...but a real duplicate on one matcher must be caught
D="$DDIR" node -e 'const fs=require("fs"),p=require("path").join(process.env.D,"settings.json");const d=JSON.parse(fs.readFileSync(p,"utf8"));d.hooks.Stop.push(JSON.parse(JSON.stringify(d.hooks.Stop[0])));fs.writeFileSync(p,JSON.stringify(d,null,2))'
doc_cli doctor claude >/dev/null 2>&1
ok $? 1 "doctor claude catches a genuinely duplicated hook"
doc_cli install claude --apply --skip-path >/dev/null 2>&1
doc_cli doctor claude >/dev/null 2>&1
ok $? 0 "re-installing collapses the duplicate again"
mkdir -p "$DDIR/plugins/installed/iriscale-voice/.claude-plugin"
printf '{"name":"iriscale-voice"}\n' > "$DDIR/plugins/installed/iriscale-voice/.claude-plugin/plugin.json"
doc_cli doctor claude 2>&1 | grep -q 'speak twice'
ok $? 0 "doctor claude warns when the plugin is also installed"
doc_cli uninstall claude --skip-path >/dev/null 2>&1


# --- migrating from the older install.ps1 install must not double up ---------------
# install.ps1 REPLACES each event with its own entry; the npm installer APPENDS. Running
# npm over a PowerShell install must recognise those entries as ours and replace them,
# not add a second copy - two entries would speak everything twice.
PS="$SANDBOX/psmix"; mkdir -p "$PS"
cat > "$PS/hooks.json" <<'EOF'
{ "hooks": {
  "UserPromptSubmit": [ { "hooks": [ { "type": "command",
    "command": "\"C:\\Users\\dev\\AppData\\Local\\Programs\\iriscale-voice\\bin\\iriscale-voice.cmd\" stamp",
    "commandWindows": "\"C:\\Users\\dev\\AppData\\Local\\Programs\\iriscale-voice\\bin\\iriscale-voice.cmd\" stamp",
    "timeout": 10 } ] } ],
  "PermissionRequest": [ { "hooks": [ { "type": "command",
    "command": "\"C:\\Users\\dev\\AppData\\Local\\Programs\\iriscale-voice\\bin\\iriscale-voice.cmd\" PermissionRequest",
    "timeout": 30 } ] } ] } }
EOF
printf 'notify = ["C:/old/iriscale-voice.cmd", "notify"]\nmodel = "gpt-5-codex"\n' > "$PS/config.toml"
CODEX_HOME="$PS" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-ps/iriscale-voice" $CLI install codex --apply --skip-path >/dev/null 2>&1
ok "$(jq_node "const d=require('$PS/hooks.json');console.log(d.hooks.UserPromptSubmit.length)")" "1" \
   "npm over an install.ps1 install leaves one UserPromptSubmit entry"
ok "$(jq_node "const d=require('$PS/hooks.json');console.log(d.hooks.PermissionRequest.length)")" "1" \
   "and one PermissionRequest entry"
ok "$(grep -c '^notify' "$PS/config.toml")" "1" "and one notify line"
has 'model = "gpt-5-codex"' "$PS/config.toml" "and keeps the user's settings"


# --- the published tarball must contain everything the installer reads at runtime ---
# Forgetting a path in package.json "files" produces a package that installs and then
# fails on someone else's machine, which no other test here would catch.
if npm pack --dry-run --json >"$SANDBOX/pack.json" 2>/dev/null; then
    missing=$(PACK="$SANDBOX/pack.json" node -e '
      const fs=require("fs")
      const files=JSON.parse(fs.readFileSync(process.env.PACK,"utf8"))[0].files.map(f=>f.path)
      const need=["bin/iriscale-voice","hooks/hooks.json","package.json",
                  "npm/cli.js","npm/core.js","npm/util.js","npm/codex.js","npm/claude.js",
                  "skills/iriscale-voice/SKILL.md","skills/iriscale-voice/agents/openai.yaml"]
      // every slash command the Claude Code installer copies must ship too
      for (const f of fs.readdirSync("commands").filter(f=>f.endsWith(".md"))) need.push("commands/"+f)
      console.log(need.filter(n=>!files.includes(n)).join(" "))
    ' 2>/dev/null)
    ok "$missing" "" "the packed tarball carries every file the installer reads"
else
    echo "  (skipped tarball contents check: npm pack --json unavailable)"
fi


# --- an install path that would break naive string substitution --------------------
ODD="$SANDBOX/od d\$x"; mkdir -p "$ODD/.claude"
CLAUDE_CONFIG_DIR="$ODD/.claude" IRISCALE_VOICE_INSTALL_ROOT="$ODD/opt/iriscale-voice" \
  $CLI install claude --apply --skip-path >/dev/null 2>&1
ok $? 0 "install claude survives a path with a space and a dollar sign"
S="$ODD/.claude/settings.json" node -e 'JSON.parse(require("fs").readFileSync(process.env.S,"utf8"))' 2>/dev/null
ok $? 0 "and still writes valid JSON"

# --- the PATH entry must survive a second agent that skips the PATH step -----------
if [ "$WINDOWS" = 0 ]; then      # the symlink half of this is POSIX-only
    SH2="$SANDBOX/shared2"; mkdir -p "$SH2/home"
    HOME="$SH2/home" CODEX_HOME="$SH2/home/.codex" IRISCALE_VOICE_INSTALL_ROOT="$SH2/opt/iriscale-voice" \
      $CLI install codex --apply >/dev/null 2>&1
    HOME="$SH2/home" CLAUDE_CONFIG_DIR="$SH2/home/.claude" IRISCALE_VOICE_INSTALL_ROOT="$SH2/opt/iriscale-voice" \
      PATH="$SH2/home/.local/bin:$PATH" $CLI install claude --apply >/dev/null 2>&1
    ok "$(jq_node "console.log(require('$SH2/opt/iriscale-voice/install.json').pathEntry !== null)")" "true" \
       "a second agent that skips PATH does not erase the first agent's entry"
    HOME="$SH2/home" CODEX_HOME="$SH2/home/.codex" IRISCALE_VOICE_INSTALL_ROOT="$SH2/opt/iriscale-voice" \
      $CLI uninstall codex >/dev/null 2>&1
    HOME="$SH2/home" CLAUDE_CONFIG_DIR="$SH2/home/.claude" IRISCALE_VOICE_INSTALL_ROOT="$SH2/opt/iriscale-voice" \
      $CLI uninstall claude >/dev/null 2>&1
    gone "$SH2/home/.local/bin/iriscale-voice" "and the last uninstall removes the symlink"
fi


# --- a Claude Code install on a machine with no ~/.claude reverts completely --------
CFRESH="$SANDBOX/cfresh"
CLAUDE_CONFIG_DIR="$CFRESH/.claude" IRISCALE_VOICE_INSTALL_ROOT="$CFRESH/opt/iriscale-voice" \
  $CLI install claude --apply --skip-path >/dev/null 2>&1
exists "$CFRESH/.claude/settings.json" "a fresh Claude Code install creates settings.json"
CLAUDE_CONFIG_DIR="$CFRESH/.claude" IRISCALE_VOICE_INSTALL_ROOT="$CFRESH/opt/iriscale-voice" \
  $CLI uninstall claude --skip-path >/dev/null 2>&1
gone "$CFRESH/.claude/settings.json" "the settings.json we created is removed again"
gone "$CFRESH/.claude"               "and so is the .claude directory we created"
ok "$(ls "$CFRESH/.claude"/*.iriscale-backup-* 2>/dev/null | wc -l | tr -d '[:space:]')" "0" \
   "leaving no backup of a file it deleted"


# --- a user's OWN hook that calls our CLI must not be mistaken for ours -------------
# `iriscale-voice say "..."` is a perfectly reasonable thing to put in your own hook.
# Matching on "contains iriscale-voice" would delete it on install; ownership is decided
# by the event argument our own entries always end with.
MINE="$SANDBOX/mine"; mkdir -p "$MINE"
cat > "$MINE/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [ { "hooks": [ { "type": "command", "command": "iriscale-voice say \"my build finished\"" } ] } ],
    "SessionEnd": [ { "hooks": [ { "type": "command", "command": "/usr/local/bin/iriscale-voice mute" } ] } ]
  }
}
EOF
CLAUDE_CONFIG_DIR="$MINE" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-mine/iriscale-voice" \
  $CLI install claude --apply --skip-path >/dev/null 2>&1
ok "$(jq_node "const d=require('$MINE/settings.json');console.log(d.hooks.Stop.filter(g=>JSON.stringify(g).includes('my build finished')).length)")" \
   "1" "a user's own 'iriscale-voice say' hook survives the install"
ok "$(jq_node "const d=require('$MINE/settings.json');console.log(d.hooks.SessionEnd.filter(g=>JSON.stringify(g).includes('mute')).length)")" \
   "1" "so does their 'iriscale-voice mute' hook"
CLAUDE_CONFIG_DIR="$MINE" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-mine/iriscale-voice" \
  $CLI uninstall claude --skip-path >/dev/null 2>&1
ok "$(jq_node "const d=require('$MINE/settings.json');console.log(d.hooks.Stop.length)")" "1" \
   "and uninstall gives back exactly their hook"
ok "$(jq_node "const d=require('$MINE/settings.json');console.log(JSON.stringify(d.hooks.Stop[0]).includes('my build finished'))")" \
   "true" "with its command intact"


# --- a user's own `notify` is displaced (Codex allows only one) and then GIVEN BACK ---
NOT="$SANDBOX/notify"; mkdir -p "$NOT"
printf 'notify = ["/usr/local/bin/my-notifier", "--json"]\nmodel = "gpt-5-codex"\n' > "$NOT/config.toml"
CODEX_HOME="$NOT" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-notify/iriscale-voice" \
  $CLI install codex --apply --skip-path >/dev/null 2>&1
has 'iriscale-voice' "$NOT/config.toml" "our notify takes the single notify slot"
ok "$(grep -c '^notify' "$NOT/config.toml")" "1" "and there is still exactly one"
# a re-install displaces OUR line, which must not overwrite the memory of theirs
CODEX_HOME="$NOT" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-notify/iriscale-voice" \
  $CLI install codex --apply --skip-path >/dev/null 2>&1
CODEX_HOME="$NOT" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-notify/iriscale-voice" \
  $CLI uninstall codex --skip-path >/dev/null 2>&1
has 'my-notifier' "$NOT/config.toml" "uninstall puts the user's own notify back"
ok "$(grep -c '^notify' "$NOT/config.toml")" "1" "and leaves exactly one notify line"
has 'model = "gpt-5-codex"' "$NOT/config.toml" "with their other settings intact"


# --- uninstall keeps your preferences, and says so --------------------------------
KEEPCFG="$SANDBOX/keepcfg"; mkdir -p "$KEEPCFG"
printf '{ "messageIdleNotifThresholdMs": 30000 }\n' > "$KEEPCFG/settings.json"   # a value the user chose must survive
CLAUDE_CONFIG_DIR="$KEEPCFG" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-keep/iriscale-voice" \
  $CLI install claude --apply --skip-path >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$KEEPCFG" sh "$root/bin/iriscale-voice" set preset verbose >/dev/null 2>&1
out=$(CLAUDE_CONFIG_DIR="$KEEPCFG" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-keep/iriscale-voice" \
  $CLI uninstall claude --skip-path 2>&1)
has '"messageIdleNotifThresholdMs": 30000' "$KEEPCFG/settings.json" "install claude never overrides a review window you chose"
exists "$KEEPCFG/iriscale-voice.conf" "uninstall keeps your settings file"
case $out in *"settings and session state are kept"*) pass=$((pass+1)) ;;
  *) fail=$((fail+1)); echo "FAIL uninstall says what it kept" ;; esac
# node prints a native path (backslashes on Windows); $KEEPCFG is cygpath -m (forward).
# Compare on one separator so this asserts the filename, not the OS.
out_slash=$(printf '%s' "$out" | tr '\\' '/')
case $out_slash in *"$KEEPCFG/iriscale-voice.conf"*) pass=$((pass+1)) ;;
  *) fail=$((fail+1)); echo "FAIL uninstall names the settings file it kept" ;; esac


# --- malformed but parseable settings.json shapes ---------------------------------
for shape in '{}' '{"hooks":null}' '{"hooks":[]}' '{"hooks":"nope"}' '{"model":"opus"}'; do
    ODDS="$SANDBOX/odd-$(printf '%s' "$shape" | tr -cd 'a-z')"; mkdir -p "$ODDS"
    printf '%s\n' "$shape" > "$ODDS/settings.json"
    CLAUDE_CONFIG_DIR="$ODDS" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-odd/iriscale-voice" \
      $CLI install claude --apply --skip-path >/dev/null 2>&1
    st=$?
    valid=$(S="$ODDS/settings.json" node -e 'const d=JSON.parse(require("fs").readFileSync(process.env.S,"utf8"));console.log(d.hooks&&Object.keys(d.hooks).length===8)' 2>/dev/null)
    if [ "$st" = 0 ] && [ "$valid" = true ]; then pass=$((pass+1))
    else fail=$((fail+1)); echo "FAIL install claude over settings.json = $shape (exit $st, 8 events: $valid)"; fi
    CLAUDE_CONFIG_DIR="$ODDS" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-odd/iriscale-voice" \
      $CLI uninstall claude --skip-path >/dev/null 2>&1
done

# a settings.json that does not parse must abort BEFORE anything is written
BADS="$SANDBOX/badsettings"; mkdir -p "$BADS"
printf 'not json {\n' > "$BADS/settings.json"
CLAUDE_CONFIG_DIR="$BADS" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-bad/iriscale-voice" \
  $CLI install claude --apply --skip-path >/dev/null 2>&1
ok $? 1 "install claude refuses a settings.json that does not parse"
ok "$(cat "$BADS/settings.json")" "not json {" "and leaves it exactly as it was"
gone "$BADS/skills" "and writes nothing else"


# --- config files that PARSE but cannot be merged into must be refused -------------
# Setting .hooks on an array or a string is dropped by JSON.stringify: we would write no
# hooks at all and report success. Refuse instead.
for bad in '[]' '"nope"' '123' 'null'; do
    BR="$SANDBOX/badroot$(printf '%s' "$bad" | tr -cd 'a-z0-9')"; mkdir -p "$BR"
    printf '%s\n' "$bad" > "$BR/settings.json"
    CLAUDE_CONFIG_DIR="$BR" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-br/iriscale-voice" \
      $CLI install claude --apply --skip-path >/dev/null 2>&1
    ok $? 1 "install claude refuses a settings.json whose root is $bad"
    ok "$(tr -d '[:space:]' < "$BR/settings.json")" "$(printf '%s' "$bad")" "and leaves it untouched"
    printf '%s\n' "$bad" > "$BR/hooks.json"
    CODEX_HOME="$BR" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-br/iriscale-voice" \
      $CLI install codex --apply --skip-path >/dev/null 2>&1
    ok $? 1 "install codex refuses a hooks.json whose root is $bad"
done

# --- a `notify` under a [table] is a DIFFERENT key and must not be touched ---------
TBL="$SANDBOX/table"; mkdir -p "$TBL"
printf '[mcp_servers.thing]\ncommand = "srv"\nnotify = ["/their/hook"]\n' > "$TBL/config.toml"
CODEX_HOME="$TBL" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-tbl/iriscale-voice" \
  $CLI install codex --apply --skip-path >/dev/null 2>&1
has '/their/hook' "$TBL/config.toml" "a notify inside a [table] is left alone"
ok "$(head -1 "$TBL/config.toml" | cut -c1-6)" "notify" "and ours is added at the top level"
ok "$(grep -c 'iriscale-voice' "$TBL/config.toml")" "1" "exactly once"

# --- a multi-line notify array must be replaced whole, not sliced -------------------
ML="$SANDBOX/multiline"; mkdir -p "$ML"
printf 'notify = [\n  "/usr/local/bin/their-notifier",\n  "--flag"\n]\nmodel = "gpt-5-codex"\n' > "$ML/config.toml"
CODEX_HOME="$ML" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-ml/iriscale-voice" \
  $CLI install codex --apply --skip-path >/dev/null 2>&1
hasnt 'their-notifier' "$ML/config.toml" "the whole multi-line notify array is replaced"
hasnt '\-\-flag' "$ML/config.toml" "leaving no orphaned array element behind"
has 'model = "gpt-5-codex"' "$ML/config.toml" "and the rest of the file survives"
CODEX_HOME="$ML" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-ml/iriscale-voice" \
  $CLI uninstall codex --skip-path >/dev/null 2>&1
has 'their-notifier' "$ML/config.toml" "and uninstall restores it in full"
has '\-\-flag' "$ML/config.toml" "including every line of it"

# --- a UTF-8 BOM must stay at the very start ---------------------------------------
BOMD="$SANDBOX/bom"; mkdir -p "$BOMD"
printf '\357\273\277model = "gpt-5-codex"\n' > "$BOMD/config.toml"
CODEX_HOME="$BOMD" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-bom/iriscale-voice" \
  $CLI install codex --apply --skip-path >/dev/null 2>&1
ok "$(head -c 3 "$BOMD/config.toml" | od -An -tx1 | tr -d ' ')" "efbbbf" "the BOM is still the first three bytes"
ok "$(tail -c +4 "$BOMD/config.toml" | head -1 | cut -c1-6)" "notify" "and notify is the first real line"


# --- a symlinked skill directory must never be followed by rm -rf -------------------
# If ~/.claude/skills/iriscale-voice is a symlink (a dotfiles setup, say), uninstall must
# unlink OUR reference and leave whatever it points at completely alone.
if [ "$WINDOWS" = 0 ]; then
    LNK="$SANDBOX/linked"; mkdir -p "$LNK/.claude/skills" "$LNK/precious/iriscale-voice"
    printf 'name: iriscale-voice\nDO NOT DELETE\n' > "$LNK/precious/iriscale-voice/SKILL.md"
    printf 'irreplaceable\n' > "$LNK/precious/iriscale-voice/keepme.txt"
    ln -s "$LNK/precious/iriscale-voice" "$LNK/.claude/skills/iriscale-voice"
    CLAUDE_CONFIG_DIR="$LNK/.claude" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-lnk/iriscale-voice" \
      $CLI install claude --apply --skip-path >/dev/null 2>&1
    CLAUDE_CONFIG_DIR="$LNK/.claude" IRISCALE_VOICE_INSTALL_ROOT="$SANDBOX/opt-lnk/iriscale-voice" \
      $CLI uninstall claude --skip-path >/dev/null 2>&1
    gone "$LNK/.claude/skills/iriscale-voice" "the symlink itself is removed"
    exists "$LNK/precious/iriscale-voice/keepme.txt" "but the directory it pointed at is untouched"
    exists "$LNK/precious/iriscale-voice/SKILL.md"   "and the skill file is still there"
    # NOTE: install deliberately writes THROUGH the symlink - that is what someone who
    # linked the directory (a dotfiles setup) wants. Only the recursive delete is refused.
    has 'irreplaceable' "$LNK/precious/iriscale-voice/keepme.txt" "with their contents intact"
fi


# --- the command an npx install puts on PATH is the SHELL SCRIPT -------------------
# It must recognise that the npm package owns the lifecycle verbs and name the exact
# command, instead of reporting a missing install.ps1 on a machine that never had one.
if [ "$WINDOWS" = 0 ]; then
    LC="$SANDBOX/lifecycle"; mkdir -p "$LC/home"
    HOME="$LC/home" CODEX_HOME="$LC/home/.codex" IRISCALE_VOICE_INSTALL_ROOT="$LC/home/.local/share/iriscale-voice" \
      $CLI install codex --apply >/dev/null 2>&1
    LINK="$LC/home/.local/bin/iriscale-voice"
    exists "$LINK" "the npx install puts iriscale-voice on PATH"
    for verb in "uninstall codex" "uninstall claude" "update" "doctor claude" "install claude --apply"; do
        out=$(HOME="$LC/home" sh "$LINK" $verb 2>&1)
        case $out in
            *"npx @iriscale/voice@latest $verb"*) pass=$((pass+1)) ;;
            *) fail=$((fail+1)); echo "FAIL '$verb' through the PATH entry names the npm command: got '$out'" ;;
        esac
        case $out in
            *install.ps1*) fail=$((fail+1)); echo "FAIL '$verb' still mentions install.ps1" ;;
            *) pass=$((pass+1)) ;;
        esac
    done
    # ...while a plain checkout, with no npm marker, keeps the old PowerShell behaviour
    out=$(sh "$root/bin/iriscale-voice" update 2>&1)
    case $out in
        *PowerShell*|*install.ps1*) pass=$((pass+1)) ;;
        *) fail=$((fail+1)); echo "FAIL a non-npm checkout should still take the PowerShell path: got '$out'" ;;
    esac
    HOME="$LC/home" CODEX_HOME="$LC/home/.codex" IRISCALE_VOICE_INSTALL_ROOT="$LC/home/.local/share/iriscale-voice" \
      $CLI uninstall codex >/dev/null 2>&1
fi


# --- an npm upgrade that leaves the stable copy behind must be visible --------------
# The hooks execute <installRoot>/bin/iriscale-voice, not node_modules, so
# `npm i -g @iriscale/voice@latest` alone upgrades the CLI and not the voice.
DR="$SANDBOX/drift"; DRROOT="$SANDBOX/opt-drift/iriscale-voice"
mkdir -p "$DR"
CLAUDE_CONFIG_DIR="$DR" IRISCALE_VOICE_INSTALL_ROOT="$DRROOT" $CLI install claude --apply --skip-path >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$DR" IRISCALE_VOICE_INSTALL_ROOT="$DRROOT" $CLI doctor claude >/dev/null 2>&1
ok $? 0 "doctor claude is clean when the copy matches the package"
# pretend the stable copy is from an older release (portable in-place edit)
S="$DRROOT/bin/iriscale-voice" node -e '
  const fs=require("fs"),p=process.env.S
  fs.writeFileSync(p, fs.readFileSync(p,"utf8").replace(/^VERSION="[^"]*"/m,"VERSION=\"0.0.1\""))'
out=$(CLAUDE_CONFIG_DIR="$DR" IRISCALE_VOICE_INSTALL_ROOT="$DRROOT" $CLI doctor claude 2>&1)
case $out in *"STALE"*"0.0.1"*) pass=$((pass+1)) ;;
  *) fail=$((fail+1)); echo "FAIL doctor claude reports a stale stable copy" ;; esac
CLAUDE_CONFIG_DIR="$DR" IRISCALE_VOICE_INSTALL_ROOT="$DRROOT" $CLI doctor claude >/dev/null 2>&1
ok $? 1 "and fails, so a script notices too"
out=$(CLAUDE_CONFIG_DIR="$DR" IRISCALE_VOICE_INSTALL_ROOT="$DRROOT" $CLI status 2>&1)
case $out in *"STALE"*) pass=$((pass+1)) ;;
  *) fail=$((fail+1)); echo "FAIL status reports a stale stable copy" ;; esac
# re-installing refreshes the copy and clears it
CLAUDE_CONFIG_DIR="$DR" IRISCALE_VOICE_INSTALL_ROOT="$DRROOT" $CLI install claude --apply --skip-path >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$DR" IRISCALE_VOICE_INSTALL_ROOT="$DRROOT" $CLI doctor claude >/dev/null 2>&1
ok $? 0 "re-installing refreshes the copy and clears the warning"
CLAUDE_CONFIG_DIR="$DR" IRISCALE_VOICE_INSTALL_ROOT="$DRROOT" $CLI uninstall claude --skip-path >/dev/null 2>&1


# --- the DEFAULT paths, with no env overrides at all -------------------------------
# Every other check sets CODEX_HOME / CLAUDE_CONFIG_DIR / IRISCALE_VOICE_INSTALL_ROOT, so
# the code that derives them from the home directory was never executed - and a missing
# export in that path survived the whole suite. Drive it with HOME alone.
if [ "$WINDOWS" = 0 ]; then
    DEF="$SANDBOX/defaults"; mkdir -p "$DEF"
    out=$(HOME="$DEF" CODEX_HOME= CLAUDE_CONFIG_DIR= IRISCALE_VOICE_INSTALL_ROOT= \
          XDG_DATA_HOME= $CLI install claude --apply 2>&1)
    ok $? 0 "install claude works with HOME alone, no overrides"
    exists "$DEF/.claude/settings.json"                  "settings.json lands under \$HOME/.claude"
    exists "$DEF/.local/share/iriscale-voice/bin/iriscale-voice" "the script lands under \$HOME/.local/share"
    exists "$DEF/.claude/commands/iriscale-voice-test.md"        "commands land under \$HOME/.claude/commands"
    HOME="$DEF" CODEX_HOME= CLAUDE_CONFIG_DIR= IRISCALE_VOICE_INSTALL_ROOT= XDG_DATA_HOME= \
      $CLI doctor claude >/dev/null 2>&1
    ok $? 0 "doctor claude works with HOME alone"
    out=$(HOME="$DEF" CODEX_HOME= CLAUDE_CONFIG_DIR= IRISCALE_VOICE_INSTALL_ROOT= \
          XDG_DATA_HOME= $CLI install codex --apply 2>&1)
    ok $? 0 "install codex works with HOME alone"
    exists "$DEF/.codex/config.toml" "config.toml lands under \$HOME/.codex"
    HOME="$DEF" CODEX_HOME= CLAUDE_CONFIG_DIR= IRISCALE_VOICE_INSTALL_ROOT= XDG_DATA_HOME= \
      $CLI uninstall codex >/dev/null 2>&1
    HOME="$DEF" CODEX_HOME= CLAUDE_CONFIG_DIR= IRISCALE_VOICE_INSTALL_ROOT= XDG_DATA_HOME= \
      $CLI uninstall claude >/dev/null 2>&1
    gone "$DEF/.local/share/iriscale-voice" "and both uninstall cleanly with HOME alone"
fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
