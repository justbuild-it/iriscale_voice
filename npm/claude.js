// Claude Code without the plugin system: the same eight hooks in settings.json, the
// skill, and the /iriscale-voice:* commands, all pointing at the stable script.
//
// The plugin remains the better route (it updates itself and needs no file edits). This
// exists for people who want one npx line for every agent, or who cannot use the
// marketplace. Installing both would speak twice, so that is refused by default.
'use strict'

const fs = require('fs')
const path = require('path')
const U = require('./util')
const core = require('./core')

const LABEL = 'Claude Code'
// ~/.claude/commands/ takes FLAT files only - a subdirectory is not a namespace there
// (only skills namespace by directory). So the plugin's /iriscale-voice:status becomes
// /iriscale-voice-status here, one flat file per command, prefixed so nothing collides.
const COMMAND_PREFIX = 'iriscale-voice-'

function claudeDir () {
  return process.env.CLAUDE_CONFIG_DIR || path.join(U.agentHome(), '.claude')
}

function paths () {
  const L = core.layout()
  const home = claudeDir()
  return {
    ...L,
    home,
    settings: path.join(home, 'settings.json'),
    skillsDir: path.join(home, 'skills'),
    skillDir: path.join(home, 'skills', 'iriscale-voice'),
    commandsDir: path.join(home, 'commands')
  }
}

// Hook commands and slash commands both run through sh; Git Bash takes forward slashes
// and they need no escaping inside JSON or Markdown.
function shPath (p) {
  return U.isWindows ? p.replace(/\\/g, '/') : p
}

// The plugin ships hooks/hooks.json with ${CLAUDE_PLUGIN_ROOT} standing in for its own
// directory. Outside the plugin system nothing sets that, so bind it to the install root
// and reuse the very same definitions - one source of truth for what fires when.
function hookGroups (L) {
  const src = path.join(U.packageRoot(), 'hooks', 'hooks.json')
  const doc = JSON.parse(U.readText(src))
  if (!doc.hooks) U.die(`${src} has no "hooks" key`)
  // Substitute into the parsed values, never the raw text: an install path containing a
  // backslash or a quote would otherwise turn valid JSON into invalid JSON.
  const root = shPath(L.root)
  const subst = v => {
    if (typeof v === 'string') return v.split('${CLAUDE_PLUGIN_ROOT}').join(root)
    if (Array.isArray(v)) return v.map(subst)
    if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, subst(x)]))
    return v
  }
  return subst(doc.hooks)
}

// Append, never replace: a user's own Stop or Notification hooks must survive, and a
// second install must not leave two copies of ours.
function mergeHooks (L, done) {
  let setWindow = false
  let doc = {}
  if (fs.existsSync(L.settings)) {
    doc = JSON.parse(U.readText(L.settings))   // pre-validated by preflight()
    U.backup(L.settings)
  }
  if (!doc.hooks || typeof doc.hooks !== 'object' || Array.isArray(doc.hooks)) doc.hooks = {}
  for (const [event, groups] of Object.entries(hookGroups(L))) {
    const existing = Array.isArray(doc.hooks[event]) ? doc.hooks[event] : []
    doc.hooks[event] = existing.filter(g => !core.isOurGroup(g)).concat(groups)
  }
  // The plugin's "reviewed" inference keys on Claude Code's idle notice, whose 60 s default
  // is too short once a finished session sits. Ten minutes, only when the user has not chosen.
  if (doc.messageIdleNotifThresholdMs === undefined) {
    doc.messageIdleNotifThresholdMs = 600000
    done.push('settings.json messageIdleNotifThresholdMs=600000 (10-minute review window)')
    setWindow = true
  }
  U.writeText(L.settings, JSON.stringify(doc, null, 2) + '\n')
  done.push('settings.json')
  return setWindow
}

function unmergeHooks (L, ours, record) {
  if (!fs.existsSync(L.settings)) return false
  let doc
  try { doc = JSON.parse(U.readText(L.settings)) } catch {
    console.error(`  skipped ${L.settings} (not valid JSON) - remove our hooks by hand`)
    return false
  }
  let changed = false
  // the review window we set at install goes too, unless the user changed it since
  if (record && record.reviewWindowSet && doc.messageIdleNotifThresholdMs === record.reviewWindowSet) {
    delete doc.messageIdleNotifThresholdMs
    changed = true
  }
  if (!doc.hooks) {
    if (changed) U.writeText(L.settings, JSON.stringify(doc, null, 2) + '\n')
    return changed
  }
  for (const [event, groups] of Object.entries(doc.hooks)) {
    if (!Array.isArray(groups)) continue
    const kept = groups.filter(g => !core.isOurGroup(g))
    if (kept.length === groups.length) continue
    changed = true
    if (kept.length) doc.hooks[event] = kept
    else delete doc.hooks[event]              // leave no empty event behind
  }
  if (!changed) return false
  if (Object.keys(doc.hooks).length === 0) delete doc.hooks
  if (!ours.has(L.settings)) U.backup(L.settings)
  U.writeText(L.settings, JSON.stringify(doc, null, 2) + '\n')
  return true
}

function copySkill (L) {
  const src = path.join(U.packageRoot(), 'skills', 'iriscale-voice')
  fs.mkdirSync(path.join(L.skillDir, 'agents'), { recursive: true })
  fs.copyFileSync(path.join(src, 'SKILL.md'), path.join(L.skillDir, 'SKILL.md'))
  fs.copyFileSync(path.join(src, 'agents', 'openai.yaml'), path.join(L.skillDir, 'agents', 'openai.yaml'))
}

// One flat file per command, prefixed: status.md -> iriscale-voice-status.md, invoked as
// /iriscale-voice-status. Returns the files written, so uninstall can take back exactly
// those and nothing else.
function commandFiles (L) {
  const src = path.join(U.packageRoot(), 'commands')
  return fs.readdirSync(src).filter(f => f.endsWith('.md'))
    .map(f => ({ from: path.join(src, f), to: path.join(L.commandsDir, COMMAND_PREFIX + f) }))
}

// Every prefixed command file of ours that is currently on disk. Going by the prefix
// rather than by what ships today is what lets install and uninstall clean up a command
// that was renamed or dropped upstream - `keep` is the set this version still wants.
// The body check keeps a user's own file that happens to share the prefix.
function ourCommandsOnDisk (L, keep) {
  const kept = new Set((keep || []).map(f => path.basename(f.to)))
  let names = []
  try { names = fs.readdirSync(L.commandsDir) } catch { return [] }
  return names
    .filter(n => n.startsWith(COMMAND_PREFIX) && n.endsWith('.md') && !kept.has(n))
    .map(n => path.join(L.commandsDir, n))
    .filter(p => { try { return U.readText(p).includes('iriscale-voice') } catch { return false } })
}

function copyCommands (L) {
  fs.mkdirSync(L.commandsDir, { recursive: true })
  const files = commandFiles(L)
  for (const { from, to } of files) {
    // Commands are authored in the plugin's own spelling. Outside the plugin they are flat
    // files invoked with a hyphen, so an example a command tells the user to run - and any
    // command it points at - has to be respelled or it simply does not exist here.
    U.writeText(to, U.readText(from)
      .split('${CLAUDE_PLUGIN_ROOT}').join(shPath(L.root))
      .split('/iriscale-voice:').join('/' + COMMAND_PREFIX))
  }
  // A command we shipped once and no longer do would otherwise sit in the picker forever,
  // calling a subcommand this script no longer has.
  for (const stale of ourCommandsOnDisk(L, files)) {
    try { fs.unlinkSync(stale) } catch {}
  }
  return files.length
}

function removeCommands (L) {
  let n = 0
  for (const { to } of commandFiles(L)) {
    // only ours: the body must still point at our script
    try { if (U.readText(to).includes('iriscale-voice')) { fs.unlinkSync(to); n++ } } catch {}
  }
  for (const stale of ourCommandsOnDisk(L, commandFiles(L))) {   // ones we shipped in an older version
    try { fs.unlinkSync(stale); n++ } catch {}
  }
  return n
}

// Both routes installed means every event fires twice - Claude Code deduplicates the same
// handler across settings files, but a plugin's copy stays separate. So refuse, rather
// than produce a stutter the user would have to debug.
//
// `enabledPlugins` in the settings files is the authoritative record of what is installed
// AND enabled; a marketplace merely being added is not. An actual plugin directory is
// checked too, so one signal failing cannot silently disable the guard.
function pluginInstalled (L) {
  const hits = []

  const settingsFiles = [
    path.join(L.home, 'settings.json'),
    path.join(L.home, 'settings.local.json'),
    path.join(process.cwd(), '.claude', 'settings.json'),
    path.join(process.cwd(), '.claude', 'settings.local.json')
  ]
  for (const file of settingsFiles) {
    let doc
    try { doc = JSON.parse(U.readText(file)) } catch { continue }
    const enabled = doc && doc.enabledPlugins
    if (!enabled || typeof enabled !== 'object') continue
    for (const [key, on] of Object.entries(enabled)) {
      if (on && /^iriscale-voice(@|$)/.test(key)) hits.push(`${key} (enabled in ${file})`)
    }
  }

  // A real installed plugin has a manifest naming it; a cached marketplace listing does not.
  const walk = (dir, depth) => {
    if (depth > 5) return
    let entries = []
    try { entries = fs.readdirSync(dir, { withFileTypes: true }) } catch { return }
    for (const e of entries) {
      if (!e.isDirectory()) continue
      const full = path.join(dir, e.name)
      const manifest = path.join(full, '.claude-plugin', 'plugin.json')
      try {
        if (JSON.parse(U.readText(manifest)).name === 'iriscale-voice') { hits.push(full); continue }
      } catch {}
      walk(full, depth + 1)
    }
  }
  walk(path.join(L.home, 'plugins'), 0)

  return [...new Set(hits)]
}

function preflight (L, argv) {
  core.preflight()
  for (const f of [path.join(U.packageRoot(), 'hooks', 'hooks.json'), path.join(U.packageRoot(), 'commands')]) {
    if (!fs.existsSync(f)) U.die(`the package is missing ${f} - reinstall iriscale-voice`)
  }
  if (fs.existsSync(L.settings)) {
    let doc
    try { doc = JSON.parse(U.readText(L.settings)) } catch {
      U.die(`${L.settings} is not valid JSON; fix or move it aside, then re-run. Nothing was changed.`)
    }
    // Parsing is not enough. Setting .hooks on an array or a string is silently lost by
    // JSON.stringify, so we would report success having written no hooks at all.
    if (!U.isPlainObject(doc)) {
      U.die(`${L.settings} is JSON but not an object (found ${Array.isArray(doc) ? 'an array' : typeof doc}); ` +
            'fix or move it aside, then re-run. Nothing was changed.')
    }
  }
  const hits = pluginInstalled(L)
  if (hits.length && !argv.includes('--force')) {
    U.die('the Claude Code plugin is already installed:\n' +
          hits.map(h => `  ${h}`).join('\n') +
          '\nInstalling both makes every event speak twice. Either keep the plugin (recommended -\n' +
          'it updates itself), or remove it with `/plugin uninstall iriscale-voice@iriscale` and\n' +
          're-run. Pass --force only if you know the plugin is inactive. Nothing was changed.')
  }
}

function install (argv) {
  const L = paths()
  preflight(L, argv)
  const done = []
  const created = [L.home, L.settings, L.skillsDir, L.commandsDir]
    .filter(p => !fs.existsSync(p))
    .concat(commandFiles(L).map(f => f.to).filter(p => !fs.existsSync(p)))

  try {
    core.materialize(L)
    fs.mkdirSync(L.home, { recursive: true })
    copySkill(L)
    const commands = copyCommands(L)
    const pathResult = argv.includes('--skip-path') ? { skipped: '--skip-path' } : core.linkOnPath(L)
    core.recordAgent(L, 'claude', { home: L.home, created, pathEntry: pathResult.added || null })
    // remembered so uninstall can take the window back - only the value we set, only if unchanged
    if (mergeHooks(L, done)) core.recordAgent(L, 'claude', { reviewWindowSet: 600000 })

    if (argv.includes('--quiet')) return 0
    core.report(LABEL, L, pathResult, [
      ['settings:', L.settings], ['skill:', L.skillDir],
      ['commands:', `${commands} in ${L.commandsDir} (/${COMMAND_PREFIX}status, ...)`]
    ])
    console.log(`Restart Claude Code, then run /${COMMAND_PREFIX}test - you should hear it.`)
    core.pathAdvice(pathResult)
    return 0
  } catch (err) {
    if (done.length) {
      console.error(`Install failed after these steps completed: ${done.join(', ')}.`)
      console.error('Backups sit next to the edited files as *.iriscale-backup-*. Re-run to finish, or run `iriscale-voice uninstall claude` to revert.')
    }
    U.die(err.message)
  }
}

// Deleting a directory is the one irreversible thing an uninstall does, so it happens
// only inside the config directory we were pointed at. A symlink is unlinked, never
// followed: rm -rf through someone's symlink would destroy a target we never installed.
// This never calls U.die - that is process.exit, and the rest of the uninstall (commands,
// marker, PATH entry) still has to run.
function removeDirIfOurs (L, dir, proof) {
  let link
  try { link = fs.lstatSync(dir) } catch { return false }
  if (link.isSymbolicLink()) {
    let target = '(unreadable)'
    try { target = fs.readlinkSync(dir) } catch {}
    fs.unlinkSync(dir)                        // drop our reference; leave the target alone
    console.error(`  note: ${dir} was a symlink to ${target} - removed the link, left the target`)
    return true
  }
  if (proof && !fs.existsSync(proof)) return false
  const resolved = fs.realpathSync(dir)
  if (path.basename(resolved) !== 'iriscale-voice') return false
  let home
  try { home = fs.realpathSync(L.home) } catch { return false }
  if (!resolved.startsWith(home + path.sep)) {
    console.error(`  kept ${resolved} - it resolves outside ${home}; remove it by hand if it is ours`)
    return false
  }
  fs.rmSync(resolved, { recursive: true, force: true })
  return true
}

function uninstall (argv) {
  const L = paths()
  const marker = core.readMarker()
  const record = (marker && marker.agents && marker.agents.claude) || {}
  const ours = new Set(record.created || [])
  const removed = []

  if (unmergeHooks(L, ours, record)) removed.push('settings.json hooks')
  if (removeDirIfOurs(L, L.skillDir, path.join(L.skillDir, 'SKILL.md'))) removed.push('skill')
  const gone = removeCommands(L)
  if (gone) removed.push(`${gone} commands`)
  removed.push(...core.returnCreated(record.created || []))

  let summary = removed.filter(r => !(r === 'settings.json hooks' && removed.includes('settings.json')))
  const { removedShared, last } = core.forgetAgent(L, 'claude')
  summary = summary.concat(removedShared)
  console.log(summary.length
    ? `Iriscale Voice uninstalled for ${LABEL} (${summary.join(', ')}). Restart Claude Code.`
    : `Nothing to uninstall - no ${LABEL} configuration found.`)
  // Only once everything is gone is there anything left for npm to remove.
  if (last) {
    core.reportLeftovers()
    console.log('Installed with npm as well? Finish with: npm uninstall -g @iriscale/voice')
  }
  return 0
}

// The Claude Code counterpart of the shell script's `doctor codex`. Its most useful job
// is catching the double-speak case after the fact: plugin AND settings hooks installed.
function doctor () {
  const L = paths()
  let failed = 0
  const ok = m => console.log(`  OK    ${m}`)
  const bad = m => { failed = 1; console.log(`  ERROR ${m}`) }

  console.log('Claude Code voice configuration')

  const wanted = Object.keys(hookGroups(L))
  if (!fs.existsSync(L.settings)) {
    bad(`no settings file: ${L.settings}`)
  } else {
    let doc = null
    try { doc = JSON.parse(U.readText(L.settings)) } catch { bad(`${L.settings} is not valid JSON`) }
    const have = doc && doc.hooks
      ? wanted.filter(e => Array.isArray(doc.hooks[e]) && doc.hooks[e].some(core.isOurGroup))
      : []
    if (have.length === wanted.length) ok(`settings.json has all ${wanted.length} hook events`)
    else bad(`settings.json has ${have.length} of ${wanted.length} hook events` +
             (have.length ? ` (missing: ${wanted.filter(e => !have.includes(e)).join(', ')})` : ''))
    // A duplicate of our own entry would speak that event twice - but Notification
    // legitimately carries two of ours under DIFFERENT matchers (idle_prompt and
    // agent_completed), so duplicates are counted per matcher, not per event.
    for (const e of wanted) {
      const mine = (doc && doc.hooks && Array.isArray(doc.hooks[e]) ? doc.hooks[e] : []).filter(core.isOurGroup)
      const perMatcher = {}
      for (const g of mine) perMatcher[g.matcher || ''] = (perMatcher[g.matcher || ''] || 0) + 1
      for (const [matcher, n] of Object.entries(perMatcher)) {
        if (n > 1) bad(`${e}${matcher ? ` [${matcher}]` : ''} has ${n} iriscale-voice entries - it would speak ${n} times`)
      }
    }
  }

  fs.existsSync(path.join(L.skillDir, 'SKILL.md')) ? ok('the skill is installed')
    : bad(`no skill at ${L.skillDir}`)

  const commands = commandFiles(L).filter(f => fs.existsSync(f.to)).length
  commands ? ok(`${commands} slash commands installed (/${COMMAND_PREFIX}status, ...)`)
    : bad(`no /${COMMAND_PREFIX}* commands in ${L.commandsDir}`)

  if (!fs.existsSync(L.script)) bad(`the hooks point at ${L.script}, which does not exist`)
  else {
    try { fs.accessSync(L.script, fs.constants.X_OK); ok('the script the hooks point at is executable') }
    catch { bad(`${L.script} is not executable`) }
  }

  const stale = core.driftWarning()
  if (stale) { failed = 1; console.log(`  ${stale}`) }

  const hits = pluginInstalled(L)
  if (hits.length) {
    bad('the Claude Code plugin is ALSO installed - every event will speak twice:\n' +
        hits.map(h => `          ${h}`).join('\n') +
        '\n        Keep one: `/plugin uninstall iriscale-voice@iriscale`, or `iriscale-voice uninstall claude`.')
  } else ok('the plugin is not also installed (no double speech)')

  console.log('  CHECK Restart Claude Code after any change to settings.json.')
  if (!failed) console.log('  READY Claude Code is configured to speak.')
  return failed
}

function plan () {
  const L = paths()
  const lines = []
  lines.push(`# ${L.settings} - merge into the "hooks" key:`)
  lines.push(JSON.stringify({ hooks: hookGroups(L) }, null, 2))
  lines.push('# also "messageIdleNotifThresholdMs": 600000 unless you already set one (the 10-minute review window)')
  lines.push('')
  lines.push(`# skill    -> ${L.skillDir}`)
  lines.push(`# commands -> ${L.commandsDir}/${COMMAND_PREFIX}*.md  (invoked as /${COMMAND_PREFIX}status, ...)`)
  return { layout: L, lines }
}

module.exports = { install, uninstall, doctor, plan, LABEL, claudeDir }
