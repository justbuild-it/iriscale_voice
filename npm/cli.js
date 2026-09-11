#!/usr/bin/env node
// npm entry point for iriscale-voice.
//
// Everything except installing is handed straight to bin/iriscale-voice, the POSIX shell
// script that IS the product. Node exists here only to (a) give Windows a working bin
// shim over Git Bash and (b) run a cross-platform installer for each agent - the
// macOS/Linux half that install.ps1 never had. No hook ever goes through node.
'use strict'

const fs = require('fs')
const path = require('path')
const { spawnSync, execFileSync } = require('child_process')
const U = require('./util')
const core = require('./core')

const AGENTS = { codex: require('./codex'), claude: require('./claude') }
const AGENT_NAMES = Object.keys(AGENTS)
const SCRIPT = path.join(U.packageRoot(), 'bin', 'iriscale-voice')

function passthrough (argv) {
  const { cmd, args } = U.shellFor(SCRIPT)
  const r = spawnSync(cmd, args.concat(argv), { stdio: 'inherit' })
  if (r.error) U.die(`could not run ${cmd}: ${r.error.message}`)
  return r.status === null ? 1 : r.status
}

function usageAgent (verb) {
  process.stderr.write(`usage: iriscale-voice ${verb} <${AGENT_NAMES.join('|')}>\n`)
  return 2
}

// What `--apply` would write, with this machine's paths filled in - for people who would
// rather paste it themselves than let an installer touch their files.
function printPlan (agent) {
  const { layout: L, lines } = AGENTS[agent].plan()
  console.log(`# ${AGENTS[agent].LABEL}: add --apply to write this for you (backing up every file it edits).`)
  console.log(`# The paths below live in ${L.root} - a fixed location, unlike an npx`)
  console.log('# cache or a global install under nvm, both of which move or vanish.')
  if (U.isWindows) {
    console.log('# Windows setup includes the shell script and .cmd launcher, plus the Codex JSON bridge:')
    console.log(`#   ${L.notifyBridge}`)
    console.log(`# Run iriscale-voice install ${agent} --apply to create these files and register the configuration.`)
  } else if (!fs.existsSync(L.script)) {
    // Pasting the config is only half the job if nothing has been installed yet.
    console.log('#')
    console.log('# The script is NOT there yet. Put it there first (or just use --apply):')
    console.log(`#   mkdir -p "${L.binDir}"`)
    console.log(`#   cp "${core.packagedScript()}" "${L.script}"`)
    console.log(`#   chmod 755 "${L.script}"`)
  }
  console.log('')
  for (const line of lines) console.log(line)
  return 0
}

// A Windows box may carry an install.ps1 install from before npm existed. That one owns
// a PowerShell profile line we know nothing about, so let it undo itself.
function legacyPowerShellInstall () {
  return U.isWindows && !core.readMarker() && fs.existsSync(path.join(U.installRoot(), 'install.ps1'))
}

// npm on Windows is npm.cmd, and since Node 18.20.2 spawning a .cmd without a shell
// throws EINVAL. `shell: true` is safe HERE and only here because every argument is a
// fixed literal - never append anything user-supplied to these arrays.
const npmOpts = U.isWindows ? { shell: true } : {}

function globalPackageDir () {
  try {
    const root = execFileSync(U.npmBin, ['root', '-g'], { encoding: 'utf8', ...npmOpts }).trim()
    const dir = path.join(root, ...core.packageName().split('/'))
    return fs.realpathSync(dir) === fs.realpathSync(U.packageRoot()) ? dir : null
  } catch { return null }
}

// Upgrade the package, then re-apply every agent it is currently installed for, so the
// stable copy and the configs never drift apart.
function update () {
  const marker = core.readMarker()
  const installed = Object.keys((marker && marker.agents) || {})
  let dir = U.packageRoot()
  if (globalPackageDir()) {
    console.log('Fetching the latest release from npm...')
    const r = spawnSync(U.npmBin, ['install', '-g', '@iriscale/voice@latest'], { stdio: 'inherit', ...npmOpts })
    if (r.status !== 0) U.die('npm install -g @iriscale/voice@latest failed')
    dir = globalPackageDir()
    if (!dir) U.die('the upgrade completed but the global package could not be located; re-run the installer by hand')
  } else console.log(`Applying package ${core.version()} to the recorded installations.`)
  if (!installed.length) {
    console.log('Upgraded. No agent is configured yet - run: iriscale-voice install codex --apply')
    return 0
  }
  for (const agent of installed) {
    if (!AGENT_NAMES.includes(agent)) U.die(`unknown recorded agent: ${agent}`)
    const home = marker.agents[agent].home
    if (!home) U.die(`missing recorded home for ${agent}; re-run install ${agent} --apply`)
    const env = { ...process.env, [agent === 'codex' ? 'CODEX_HOME' : 'CLAUDE_CONFIG_DIR']: home }
    // Updating a runtime must not add a PATH entry that the original install skipped.
    const re = spawnSync(process.execPath, [path.join(dir, 'npm', 'cli.js'), 'install', agent, '--apply', '--skip-path'], { stdio: 'inherit', env })
    if (re.status !== 0) U.die(`the new version installed but re-applying the ${agent} configuration failed`)
  }
  console.log('Restart your agents and your terminal.')
  return 0
}

function main (argv) {
  const [cmd, ...rest] = argv

  // Bare `iriscale-voice` at a prompt: the script would treat it as a Stop hook and block
  // reading stdin. A hook always pipes JSON or passes it in argv, so a TTY here can only
  // be a human who wanted the help.
  if (!cmd && process.stdin.isTTY) return passthrough(['--help'])

  if (cmd === 'install') {
    const agent = rest[0]
    if (!AGENTS[agent]) return usageAgent('install')
    return rest.includes('--apply') ? AGENTS[agent].install(rest) : printPlan(agent)
  }
  if (cmd === 'uninstall' && !legacyPowerShellInstall()) {
    const agent = rest[0]
    if (!AGENTS[agent]) return usageAgent('uninstall')
    return AGENTS[agent].uninstall(rest)
  }
  // `doctor codex` lives in the shell script; `doctor claude` only makes sense for the
  // npx route, so it lives here. Everything else falls through untouched.
  if (cmd === 'doctor' && rest[0] === 'claude') return AGENTS.claude.doctor()
  if (cmd === 'doctor' && rest[0] === 'codex') return AGENTS.codex.doctor()
  if (cmd === 'update' && !legacyPowerShellInstall()) return update()

  // `status` and `doctor codex` live in the shell script and cannot know the package
  // version, so surface a stale stable copy around them - where the user is already
  // looking for exactly this kind of answer.
  const status = passthrough(argv)
  if (cmd === 'status' || (cmd === 'doctor' && rest[0] === 'codex')) {
    const stale = core.driftWarning()
    if (stale) console.log(`  ${stale}`)
  }
  return status
}

process.exitCode = main(process.argv.slice(2))
