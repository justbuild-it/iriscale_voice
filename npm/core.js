// The half of installing that has nothing to do with which agent you use: putting the
// script somewhere stable, putting the command on PATH, and remembering precisely what
// we created so uninstall can give it all back.
'use strict'

const fs = require('fs')
const path = require('path')
const U = require('./util')

function layout () {
  const root = U.installRoot()
  const binDir = path.join(root, 'bin')
  const script = path.join(binDir, 'iriscale-voice')
  return { root, binDir, script, notifyBridge: path.join(binDir, 'iriscale-voice-notify.ps1'),
    launcher: U.isWindows ? path.join(binDir, 'iriscale-voice.cmd') : script }
}

function packagedScript () {
  return path.join(U.packageRoot(), 'bin', 'iriscale-voice')
}

function version () {
  return require(path.join(U.packageRoot(), 'package.json')).version
}

// The published name is scoped, so npm unpacks it to node_modules/@scope/name. Read it
// from the manifest rather than hard-coding either half, so a rename cannot desync them.
function packageName () {
  return require(path.join(U.packageRoot(), 'package.json')).name
}

// Fails before anything is written, so a bad environment cannot leave a half-install.
function preflight () {
  if (!fs.existsSync(packagedScript())) U.die(`packaged script is missing: ${packagedScript()}`)
  if (U.isWindows && !U.gitBash()) {
    U.die('Git for Windows is required (it provides the shell every hook runs through).\n' +
          'Install it from https://git-scm.com/download/win and re-run.')
  }
}

// The stable copy. Hooks point here and nowhere else: an npx cache is temporary and a
// global install under nvm moves with every Node version.
function materialize (L) {
  fs.mkdirSync(L.binDir, { recursive: true })
  fs.copyFileSync(packagedScript(), L.script)
  fs.chmodSync(L.script, 0o755)      // Codex's `notify` execs it directly
  if (U.isWindows) {
    fs.copyFileSync(path.join(U.packageRoot(), 'bin', 'iriscale-voice-notify.ps1'), L.notifyBridge)
    // No --login: Git's bin\bash.exe wrapper already fixes PATH, while --login costs
    // ~550 ms per hook event and sources .bash_profile, whose output corrupts captures.
    //
    // %~dp0 is the launcher's own directory at run time, so the install path - which may
    // contain a non-ASCII user name - never has to survive a round trip through the
    // console code page a BOM-less .cmd is parsed in.
    const bash = U.gitBash()
    if (/[^\x20-\x7E]/.test(bash)) {
      console.error(`  warning: Git Bash lives at a path with non-ASCII characters (${bash}).`)
      console.error('  A .cmd file is read in the console code page, so the launcher may fail.')
      console.error('  If it does, reinstall Git for Windows somewhere ASCII-only.')
    }
    fs.writeFileSync(L.launcher, `@echo off\r\n"${bash}" "%~dp0iriscale-voice" %*\r\n`, 'latin1')
  }
}

// PATH is a convenience: every hook holds an absolute path, so voice works without it.
// Skipped when the command already resolves durably - npx's own temporary shim, which
// sits on PATH only for the length of one run, does not count.
function linkOnPath (L) {
  const existing = U.onPath('iriscale-voice')
  if (existing && !U.isEphemeralShim(existing)) return { skipped: `already on PATH at ${existing}` }
  if (U.isWindows) {
    return U.windowsPath(L.binDir, 'add')
      ? { added: L.binDir }
      : { skipped: 'could not edit the user PATH (PowerShell unavailable)' }
  }
  const dir = path.join(U.homeDir(), '.local', 'bin')
  const link = path.join(dir, 'iriscale-voice')
  fs.mkdirSync(dir, { recursive: true })
  try { fs.unlinkSync(link) } catch {}
  fs.symlinkSync(L.script, link)
  const visible = (process.env.PATH || '').split(path.delimiter).includes(dir)
  return { added: link, hintDir: visible ? null : dir }
}

function unlinkFromPath (L, marker) {
  if (U.isWindows) return U.windowsPath(L.binDir, 'remove') ? 'PATH entry' : null
  const entry = marker && marker.pathEntry
  if (!entry) return null
  try {
    if (fs.readlinkSync(entry) === L.script) { fs.unlinkSync(entry); return 'PATH symlink' }
  } catch {}
  return null
}

// One marker for the whole install; each agent gets its own record inside it, so
// uninstalling Codex cannot forget what the Claude Code install created.
function readMarker () {
  return U.readMarker()
}

function recordAgent (L, agent, record) {
  const previous = readMarker() || {}
  const agents = previous.agents || {}
  const before = agents[agent] || {}
  agents[agent] = {
    ...before,
    ...record,
    // union: a second install must not forget what the first one had to create
    created: [...new Set([...(before.created || []), ...(record.created || [])])]
  }
  U.writeText(U.markerPath(), JSON.stringify({
    version: version(),
    installer: 'npm',
    root: L.root,
    // An agent that skipped the PATH step (because the command already resolved) reports
    // null - that must not erase the entry an earlier agent actually created, or the
    // last uninstall would leave the symlink behind.
    pathEntry: record.pathEntry || previous.pathEntry || null,
    agents
  }, null, 2) + '\n')
}

// Give back files and directories we created, once they hold nothing else. Longest path
// first, so <home>/config.toml goes before <home> itself can be empty.
function returnCreated (created) {
  const back = []
  for (const p of [...new Set(created)].sort((a, b) => b.length - a.length)) {
    try {
      const st = fs.statSync(p)
      if (st.isDirectory()) { fs.rmdirSync(p); back.push(path.basename(p) + '/') }
      else if (U.isEmptyish(p)) { fs.unlinkSync(p); back.push(path.basename(p)) }
    } catch {}   // still holds something, or already gone: leave it alone
  }
  return back
}

// The install directory and the PATH entry are shared, so they go only with the last agent.
function forgetAgent (L, agent) {
  const marker = readMarker()
  if (!marker) return { removedShared: [] }
  const agents = { ...(marker.agents || {}) }
  delete agents[agent]
  const removedShared = []
  const last = Object.keys(agents).length === 0
  if (last) {
    const path_ = unlinkFromPath(L, marker)
    if (path_) removedShared.push(path_)
    if (fs.existsSync(L.root)) {
      if (path.basename(L.root) === 'iriscale-voice') {
        // On Windows the npm and PowerShell installers share this directory. If the
        // PowerShell one was here first, its $PROFILE dot-source line points into the
        // directory we are about to delete - take it with us.
        if (U.isWindows &&
            (fs.existsSync(path.join(L.root, 'install.ps1')) ||
             fs.existsSync(path.join(L.root, 'iriscale-voice-completion.ps1')))) {
          if (U.removePowerShellProfileLine()) removedShared.push('PowerShell profile line')
        }
        fs.rmSync(L.root, { recursive: true, force: true })
        removedShared.push('install directory')
      } else {
        // Everything else is undone; a root we cannot vouch for is left for the user
        // rather than deleted on a guess (a mis-set IRISCALE_VOICE_INSTALL_ROOT).
        console.error(`  kept ${L.root} - not named iriscale-voice; remove it by hand if it is ours`)
      }
    }
  } else {
    U.writeText(U.markerPath(), JSON.stringify({ ...marker, agents }, null, 2) + '\n')
    removedShared.push(`kept the install for ${Object.keys(agents).join(', ')}`)
  }
  return { removedShared, last }
}

// Recognising OUR hook entries has to be precise in both directions: loose enough to
// find them after the install path changed, tight enough that a user's own hook which
// happens to call the CLI - `iriscale-voice say "build done"` - is never mistaken for
// ours and removed. Every entry we write ends with one of the event arguments below;
// nothing a person would write by hand does.
const OUR_ARGS = new Set([
  'stamp', 'resume', 'notify', 'Stop', 'StopFailure', 'PermissionRequest', 'idle_prompt',
  'agent_completed', 'SubagentStop', 'SessionEnd', 'StepDone', 'Scheduled',
  'Remind', 'WelcomeBack', 'codex-stamp', 'codex-resume', 'codex-PermissionRequest', 'codex-Stop', 'codex-SessionEnd'
])

function isOurCommand (command) {
  if (typeof command === 'string') {
    const encoded = /^powershell\.exe -NoProfile -NonInteractive -EncodedCommand ([A-Za-z0-9+/=]+)$/.exec(command)
    if (encoded) {
      command = Buffer.from(encoded[1], 'base64').toString('utf16le')
      if (!command.startsWith('& ') || !command.endsWith('; exit $LASTEXITCODE')) return false
      command = command.slice(0, -'; exit $LASTEXITCODE'.length)
    }
  }
  if (typeof command !== 'string' || !command.includes('iriscale-voice')) return false
  const last = command.trim().split(/\s+/).pop().replace(/^["']|["']$/g, '')
  return OUR_ARGS.has(last)
}

function isOurGroup (group) {
  const hooks = group && Array.isArray(group.hooks) ? group.hooks : []
  return hooks.some(h => h && (isOurCommand(h.command) || isOurCommand(h.commandWindows)))
}

function withoutOurHooks (groups) {
  return groups.flatMap(group => {
    if (!isOurGroup(group)) return [group]
    const hooks = group.hooks.filter(h => !h || !(isOurCommand(h.command) || isOurCommand(h.commandWindows)))
    return hooks.length ? [{ ...group, hooks }] : []
  })
}

// Uninstall deliberately keeps your preferences - a reinstall should not forget your
// preset or quiet hours - but silence about it would make "uninstalled" a lie. So name
// what stayed and how to remove it.
function leftovers () {
  const dir = process.env.CLAUDE_CONFIG_DIR || path.join(U.homeDir(), '.claude')
  const state = path.join(dir, 'iriscale-voice-runtime')
  return [
    path.join(dir, 'iriscale-voice.conf'),
    path.join(dir, 'iriscale-voice.log'),
    path.join(dir, 'iriscale-voice-sessions'),
    state
  ].filter(p => fs.existsSync(p))
}

function reportLeftovers () {
  const kept = leftovers()
  if (!kept.length) return
  console.log('Your settings and session state are kept (a reinstall picks them up again).')
  console.log('For a clean slate, remove:')
  for (const p of kept) console.log(`  ${p}`)
}

// The hooks execute the stable copy, not node_modules, so `npm i -g …@latest` upgrades
// the CLI and leaves the voice on the old version. Read the version out of the file the
// hooks actually run - the marker can be out of step with it after a partial install.
function installedScriptVersion (L) {
  try {
    const m = fs.readFileSync(L.script, 'utf8').match(/^VERSION="([^"]+)"/m)
    return m ? m[1] : null
  } catch { return null }
}

function driftWarning () {
  const L = layout()
  const running = installedScriptVersion(L)
  if (!running || running === version()) return null
  return `STALE  your hooks run ${running}, but this package is ${version()} - run: iriscale-voice update`
}

function report (agentLabel, L, pathResult, extra) {
  console.log(`Iriscale Voice installed for ${agentLabel}.`)
  console.log(`  executable:   ${L.launcher}`)
  console.log(`  version:      ${version()}`)
  for (const [k, v] of extra) console.log(`  ${k.padEnd(13)} ${v}`)
  if (pathResult.added) console.log(`  PATH:         ${pathResult.added}`)
  if (pathResult.skipped) console.log(`  PATH:         unchanged (${pathResult.skipped})`)
}

function pathAdvice (pathResult) {
  if (!pathResult.hintDir) return
  // The hooks hold absolute paths, so this is about the CLI only - say so, or it reads
  // as "the install did not work".
  console.log('')
  console.log('Voice works either way: the hooks use absolute paths, not PATH.')
  console.log('To run iriscale-voice yourself (status, board, test), add its directory:')
  console.log(`  ${U.pathHint(pathResult.hintDir)}`)
  console.log('Or install the command globally instead: npm install -g @iriscale/voice')
}

module.exports = {
  layout, packagedScript, version, packageName, preflight, materialize, linkOnPath, unlinkFromPath,
  isOurGroup, isOurCommand, withoutOurHooks, reportLeftovers, driftWarning, installedScriptVersion,
  readMarker, recordAgent, returnCreated, forgetAgent, report, pathAdvice
}
