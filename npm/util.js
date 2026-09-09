// Shared helpers for the npm installer. Node is an INSTALL-time dependency only:
// nothing here runs on the hook path — hooks call bin/iriscale-voice with sh.
'use strict'

const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync, spawnSync } = require('child_process')

const isWindows = process.platform === 'win32'

// Tests redirect HOME; honour it on every platform so a test run can never touch the
// real ~/.codex. On Windows outside a test, HOME is usually unset and USERPROFILE wins.
function homeDir () {
  return process.env.HOME || process.env.USERPROFILE || os.homedir()
}

// Where the stable copy lives. Hooks and `notify` point INTO this directory, never at
// the npm cache (npx) or a versioned node path (nvm) - both move or vanish.
function installRoot () {
  if (process.env.IRISCALE_VOICE_INSTALL_ROOT) return process.env.IRISCALE_VOICE_INSTALL_ROOT
  if (isWindows) {
    const base = process.env.LOCALAPPDATA || path.join(homeDir(), 'AppData', 'Local')
    return path.join(base, 'Programs', 'iriscale-voice')  // same root install.ps1 uses
  }
  const base = process.env.XDG_DATA_HOME || path.join(homeDir(), '.local', 'share')
  return path.join(base, 'iriscale-voice')
}

// Where the AGENT keeps its configuration. On Windows that is the real user profile:
// Git Bash often sets HOME to something Codex and Claude Code never read. Our own state
// (config, log, sessions) deliberately keeps following HOME, because that is what
// bin/iriscale-voice itself uses - see homeDir().
function agentHome () {
  return isWindows ? (process.env.USERPROFILE || os.homedir()) : homeDir()
}

function codexHome () {
  return process.env.CODEX_HOME || path.join(agentHome(), '.codex')
}

function packageRoot () {
  return path.resolve(__dirname, '..')
}

function markerPath () {
  return path.join(installRoot(), 'install.json')
}

function readMarker () {
  try { return JSON.parse(fs.readFileSync(markerPath(), 'utf8')) } catch { return null }
}

// Backups sit next to the file as *.iriscale-backup-* (matched by .gitignore), exactly
// like install.ps1, so both installers leave the same trail.
function backup (file) {
  if (!fs.existsSync(file)) return null
  // Re-running the installer must not pile up identical copies of our own output.
  const current = fs.readFileSync(file)
  const dir = path.dirname(file)
  const prefix = `${path.basename(file)}.iriscale-backup-`
  const twin = fs.readdirSync(dir).filter(f => f.startsWith(prefix))
    .some(f => { try { return fs.readFileSync(path.join(dir, f)).equals(current) } catch { return false } })
  if (twin) return null
  const d = new Date()
  const p = n => String(n).padStart(2, '0')
  const stamp = `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-` +
                `${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`
  const dest = `${file}.iriscale-backup-${stamp}`
  fs.copyFileSync(file, dest)
  return dest
}

// Keep a file's existing line ending; a CRLF config.toml stays CRLF.
function eolOf (text) {
  return text.includes('\r\n') ? '\r\n' : '\n'
}

function writeText (file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, content, 'utf8')   // UTF-8, no BOM
}

// A UTF-8 BOM is invisible but real: leaving it in the first line means a `notify` we
// prepend lands AFTER it, and everything shifts by three bytes.
const BOM = '\uFEFF'

function readText (file) {
  const text = fs.readFileSync(file, 'utf8')
  return text.startsWith(BOM) ? text.slice(1) : text
}

function hadBom (file) {
  try { return fs.readFileSync(file, 'utf8').startsWith(BOM) } catch { return false }
}

// A plain JSON object - not an array, not null, not a scalar. Config files whose root is
// anything else cannot be merged into, and must be refused rather than silently rewritten.
function isPlainObject (v) {
  return !!v && typeof v === 'object' && !Array.isArray(v)
}

// Git for Windows ships the sh that every hook runs through. bin\bash.exe is the
// WRAPPER - it puts /usr/bin on PATH, so date/tr/mkdir exist. usr\bin\bash.exe does
// not, and hooks then die with "date: command not found".
function gitBash () {
  const candidates = []
  const pf = process.env.ProgramFiles
  const pf86 = process.env['ProgramFiles(x86)']
  const local = process.env.LOCALAPPDATA
  if (pf) candidates.push(path.join(pf, 'Git', 'bin', 'bash.exe'))
  if (pf86) candidates.push(path.join(pf86, 'Git', 'bin', 'bash.exe'))
  // the documented non-admin ("just me") install location
  if (local) candidates.push(path.join(local, 'Programs', 'Git', 'bin', 'bash.exe'))

  // Derive Git's root from git.exe, which IS on PATH because the installer always adds
  // <git>\cmd. This covers admin, non-admin, custom-drive, scoop and portable installs
  // without guessing at directories.
  const where = spawnSync('where', ['git.exe'], { encoding: 'utf8' })
  if (where.status === 0) {
    for (const hit of where.stdout.split(/\r?\n/).map(x => x.trim()).filter(Boolean)) {
      // <git>\cmd\git.exe, <git>\bin\git.exe, <git>\mingw64\bin\git.exe
      for (const up of [2, 3]) {
        const root = path.resolve(hit, ...Array(up).fill('..'))
        candidates.push(path.join(root, 'bin', 'bash.exe'))
      }
    }
  }

  // NOTE: never `where bash.exe`. On a machine with WSL that finds
  // C:\Windows\System32\bash.exe, which is the Linux subsystem - it cannot see the
  // Windows filesystem the way our hooks need and would silently break every event.
  // Git's bin\bash.exe is also the WRAPPER: it puts /usr/bin on PATH, so date/tr/mkdir
  // exist. usr\bin\bash.exe does not, and hooks die with "date: command not found".
  return candidates.find(c => !/\\Windows\\System32\\/i.test(c) && fs.existsSync(c)) || null
}

// The interpreter for pass-through commands (status, board, config, ...).
function shellFor (script) {
  if (!isWindows) return { cmd: '/bin/sh', args: [script] }
  const bash = gitBash()
  if (!bash) {
    die('Git for Windows is required (it provides the shell every hook runs through).\n' +
        'Install it from https://git-scm.com/download/win and try again.')
  }
  return { cmd: bash, args: [script] }
}

function onPath (name) {
  try {
    // `command -v` is a shell builtin, so it needs a shell - but pass the name as $1
    // rather than interpolating it, and never as spawn's `shell: true`.
    const r = isWindows
      ? spawnSync('where', [name], { encoding: 'utf8' })
      : spawnSync('/bin/sh', ['-c', 'command -v "$1"', 'sh', name], { encoding: 'utf8' })
    if (r.status !== 0) return null
    return r.stdout.split(/\r?\n/)[0].trim() || null
  } catch { return null }
}

// npx unpacks into ~/.npm/_npx/<hash>/ and puts that node_modules/.bin on PATH for the
// duration of the run. A hit there means the command is on PATH *right now* and gone a
// second later - it must not be mistaken for an installed one.
function isEphemeralShim (resolved) {
  return /[\\/]_npx[\\/]/.test(resolved)
}

// npm itself is a .cmd shim on Windows; naming it directly avoids spawning a shell.
const npmBin = isWindows ? 'npm.cmd' : 'npm'

// Windows user PATH, edited the way install.ps1 does it. `setx` is NOT used: it
// truncates PATH at 1024 characters and has eaten people's environments.
function windowsPath (dir, action) {
  const quoted = `'${dir.replace(/'/g, "''")}'`
  const script = action === 'add'
    ? `$b=${quoted}; $p=[string][Environment]::GetEnvironmentVariable('Path','User'); ` +
      `if (@($p -split ';') -notcontains $b) { [Environment]::SetEnvironmentVariable('Path', (($p.TrimEnd(';') + ';' + $b).TrimStart(';')), 'User') }`
    : `$b=${quoted}; $p=[string][Environment]::GetEnvironmentVariable('Path','User'); ` +
      `$parts=@($p -split ';' | Where-Object { $_ -and $_ -ne $b }); [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')`
  try {
    execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script], { stdio: 'ignore' })
    return true
  } catch { return false }
}

// A file we created and that now holds nothing of the user's is ours to remove again.
function isEmptyish (file) {
  let text
  try { text = fs.readFileSync(file, 'utf8') } catch { return false }
  if (text.trim() === '') return true
  try {
    const doc = JSON.parse(text)
    if (!doc || typeof doc !== 'object' || Array.isArray(doc)) return false
    const keys = Object.keys(doc)
    if (keys.length === 0) return true                                  // settings.json -> {}
    return keys.length === 1 && !!doc.hooks && typeof doc.hooks === 'object' &&
           Object.keys(doc.hooks).length === 0                          // hooks.json -> {"hooks":{}}
  } catch { return false }
}

// The exact line that puts `dir` on PATH, for the shell the user is actually running.
function pathHint (dir) {
  const home = homeDir()
  const shown = dir.startsWith(home) ? '$HOME' + dir.slice(home.length) : dir
  const shell = path.basename(process.env.SHELL || 'sh')
  if (shell === 'fish') return `fish_add_path ${shown}`
  const rc = shell === 'zsh' ? '~/.zshrc' : shell === 'bash' ? '~/.bashrc' : '~/.profile'
  return `echo 'export PATH="${shown}:$PATH"' >> ${rc} && exec ${shell}`
}

// install.ps1 adds a dot-source line to the PowerShell $PROFILE for tab completion. If
// the npm uninstaller removes the install directory it must take that line with it, or
// every new PowerShell session errors on a file that no longer exists.
function removePowerShellProfileLine () {
  const script = [
    "if (Test-Path -LiteralPath $PROFILE) {",
    '  $lines = @(Get-Content -LiteralPath $PROFILE)',
    "  $kept = @($lines | Where-Object { $_ -notmatch 'iriscale-voice completion' -and $_ -notmatch 'iriscale-voice-completion\.ps1' })",
    '  if ($kept.Count -ne $lines.Count) {',
    "    Copy-Item -LiteralPath $PROFILE -Destination \"$PROFILE.iriscale-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')\"",
    '    [IO.File]::WriteAllText($PROFILE, ($kept -join [Environment]::NewLine) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))',
    "    Write-Output 'removed'",
    '  }',
    '}'
  ].join(' ')
  try {
    const out = execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script], { encoding: 'utf8' })
    return out.includes('removed')
  } catch { return false }
}

function die (message) {
  process.stderr.write(`iriscale-voice: ${message}\n`)
  process.exit(1)
}

module.exports = {
  isWindows, npmBin, isEphemeralShim, homeDir, agentHome, installRoot, codexHome, packageRoot, markerPath, readMarker,
  backup, isEmptyish, pathHint, eolOf, hadBom, isPlainObject, BOM, removePowerShellProfileLine, writeText, readText, gitBash, shellFor, onPath, windowsPath, die
}
