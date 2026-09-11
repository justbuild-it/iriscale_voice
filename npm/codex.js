// Codex CLI: `notify` plus three hooks in ~/.codex, and the $iriscale-voice skill.
// The cross-platform equivalent of install.ps1.
'use strict'

const fs = require('fs')
const path = require('path')
const U = require('./util')
const core = require('./core')
const { findTopLevelNotify } = require('./toml')

const LABEL = 'Codex'

const HOOK_EVENTS = [
  { event: 'UserPromptSubmit', arg: 'stamp', timeout: 10 },
  { event: 'PermissionRequest', arg: 'PermissionRequest', timeout: 30 },
  { event: 'PostToolUse', arg: 'resume', timeout: 10 }
]

function paths () {
  const L = core.layout()
  const home = U.codexHome()
  return {
    ...L,
    home,
    config: path.join(home, 'config.toml'),
    hooks: path.join(home, 'hooks.json'),
    skillsDir: path.join(home, 'skills'),
    skillDir: path.join(home, 'skills', 'iriscale-voice')
  }
}

// TOML basic string: forward slashes on Windows so no backslash needs escaping.
function tomlPath (p) {
  return JSON.stringify(U.isWindows ? p.replace(/\\/g, '/') : p).slice(1, -1)
}

function notifyLine (L) {
  return `notify = ["${tomlPath(L.launcher)}", "notify"]`
}

// On Windows both `command` and `commandWindows` carry the launcher: Codex 0.147
// requires the portable field even when the override is present, and shows
// "Installed 0" without it.
function hookCommand (L, arg) {
  return U.isWindows ? `"${L.launcher}" ${arg}` : `sh '${L.script.replace(/'/g, "'\\''")}' ${arg}`
}

function hookEntry (L, arg, timeout) {
  const hook = { type: 'command', command: hookCommand(L, arg), timeout }
  if (U.isWindows) hook.commandWindows = hook.command
  return [{ hooks: [hook] }]
}

// Find the TOP-LEVEL `notify`, and only that. A `notify = ...` under a [table] header
// belongs to that table and is a different key entirely - overwriting it would destroy a
// user's setting AND leave the real top-level notify unset, so voice would never fire.
// The TOML scanner is shared with installer diagnostics in ./toml.

// Codex supports exactly one top-level `notify`, so ours has to take the place of any
// other. Returns the value it displaced (if it was somebody else's) so uninstall can put
// it back rather than leaving the user to dig it out of the backup.
function mergeNotify (L, done) {
  let lines = []
  let eol = U.isWindows ? '\r\n' : '\n'
  let bom = false
  if (fs.existsSync(L.config)) {
    const text = U.readText(L.config)
    eol = U.eolOf(text)
    bom = U.hadBom(L.config)
    U.backup(L.config)
    lines = text.split(/\r?\n/)
    if (lines.length && lines[lines.length - 1] === '') lines.pop()
  }
  const line = notifyLine(L)
  const span = findTopLevelNotify(lines)
  let displaced = null
  if (span) {
    const [from, to] = span
    const old = lines.slice(from, to + 1)
    if (!old.join('\n').includes('iriscale-voice')) displaced = old
    lines.splice(from, to - from + 1, line)
  } else {
    lines = [line, ''].concat(lines)   // top-level key: must precede any [table]
  }
  U.writeText(L.config, (bom ? U.BOM : '') + lines.join(eol) + eol)
  done.push('config.toml')
  return displaced
}

// Append, never replace: a user's own UserPromptSubmit hook must survive, and a second
// install must not leave two copies of ours.
function mergeHooks (L, done) {
  let doc = { hooks: {} }
  if (fs.existsSync(L.hooks)) {
    doc = JSON.parse(U.readText(L.hooks))   // pre-validated by preflight()
    U.backup(L.hooks)
  }
  if (!doc.hooks || typeof doc.hooks !== 'object' || Array.isArray(doc.hooks)) doc.hooks = {}
  for (const { event, arg, timeout } of HOOK_EVENTS) {
    const existing = Array.isArray(doc.hooks[event]) ? doc.hooks[event] : []
    doc.hooks[event] = core.withoutOurHooks(existing).concat(hookEntry(L, arg, timeout))
  }
  U.writeText(L.hooks, JSON.stringify(doc, null, 2) + '\n')
  done.push('hooks.json')
}

function copySkill (L) {
  const src = path.join(U.packageRoot(), 'skills', 'iriscale-voice')
  fs.mkdirSync(path.join(L.skillDir, 'agents'), { recursive: true })
  fs.copyFileSync(path.join(src, 'SKILL.md'), path.join(L.skillDir, 'SKILL.md'))
  fs.copyFileSync(path.join(src, 'agents', 'openai.yaml'), path.join(L.skillDir, 'agents', 'openai.yaml'))
}

function preflight (L) {
  core.preflight()
  if (fs.existsSync(L.config)) findTopLevelNotify(U.readText(L.config).split(/\r?\n/))
  if (fs.existsSync(L.hooks)) {
    let doc
    try { doc = JSON.parse(U.readText(L.hooks)) } catch {
      U.die(`${L.hooks} is not valid JSON; fix or move it aside, then re-run. Nothing was changed.`)
    }
    // Parsing is not enough: a root of [] or "x" cannot be merged into, and quietly
    // writing zero hooks while reporting success is the worst outcome.
    if (!U.isPlainObject(doc)) {
      U.die(`${L.hooks} is JSON but not an object (found ${Array.isArray(doc) ? 'an array' : typeof doc}); ` +
            'fix or move it aside, then re-run. Nothing was changed.')
    }
  }
}

function install (argv) {
  const L = paths()
  preflight(L)
  const done = []
  const created = [L.home, L.config, L.hooks, L.skillsDir].filter(p => !fs.existsSync(p))

  try {
    core.materialize(L)
    fs.mkdirSync(L.home, { recursive: true })
    copySkill(L)
    const pathResult = argv.includes('--skip-path') ? { skipped: '--skip-path' } : core.linkOnPath(L)
    const previous = (core.readMarker() || {}).agents || {}
    // Preserve the displaced notify when moving from the standalone Windows installer.
    let legacy = {}
    try { legacy = JSON.parse(U.readText(path.join(L.root, 'powershell-install.json'))) } catch {}
    const displaced = mergeNotify(L, done)
    mergeHooks(L, done)
    core.recordAgent(L, 'codex', {
      home: L.home,
      created,
      pathEntry: pathResult.added || null,
      // a re-install displaces our own line, which is not the user's - keep the first one
      replacedNotify: displaced || (previous.codex && previous.codex.replacedNotify) || legacy.replacedNotify || null
    })

    if (argv.includes('--quiet')) return 0
    core.report(LABEL, L, pathResult, [
      ['Codex config:', L.config], ['Codex hooks:', L.hooks], ['Codex skill:', L.skillDir]
    ])
    console.log('Restart Codex and your terminal, then open /hooks and trust the hooks showing Installed 1.')
    core.pathAdvice(pathResult)
    return 0
  } catch (err) {
    if (done.length) {
      console.error(`Install failed after these steps completed: ${done.join(', ')}.`)
      console.error('Backups sit next to the edited files as *.iriscale-backup-*. Re-run to finish, or run `iriscale-voice uninstall codex` to revert.')
    }
    U.die(err.message)
  }
}

function unmergeNotify (L, ours, replacedNotify) {
  if (!fs.existsSync(L.config)) return false
  const text = U.readText(L.config)
  const eol = U.eolOf(text)
  const bom = U.hadBom(L.config)
  const lines = text.split(/\r?\n/)
  const span = findTopLevelNotify(lines)
  if (!span || !lines.slice(span[0], span[1] + 1).join('\n').includes('iriscale-voice')) return false
  if (!ours.has(L.config)) U.backup(L.config)   // never back up a file we then delete
  // Put the user's own notify back where ours sat, rather than leaving them without one.
  const restored = replacedNotify ? (Array.isArray(replacedNotify) ? replacedNotify : [replacedNotify]) : []
  lines.splice(span[0], span[1] - span[0] + 1, ...restored)
  while (lines.length && lines[lines.length - 1] === '') lines.pop()
  U.writeText(L.config, (bom ? U.BOM : '') + lines.join(eol) + eol)
  return restored.length ? 'config.toml notify (yours restored)' : true
}

function unmergeHooks (L, ours) {
  if (!fs.existsSync(L.hooks)) return false
  let doc
  try { doc = JSON.parse(U.readText(L.hooks)) } catch {
    console.error(`  skipped ${L.hooks} (not valid JSON) - remove our hooks by hand`)
    return false
  }
  if (!doc.hooks) return false
  let changed = false
  for (const [event, groups] of Object.entries(doc.hooks)) {
    if (!Array.isArray(groups)) continue
    const kept = core.withoutOurHooks(groups)
    if (JSON.stringify(kept) === JSON.stringify(groups)) continue
    changed = true
    if (kept.length) doc.hooks[event] = kept
    else delete doc.hooks[event]              // leave no empty event behind
  }
  if (!changed) return false
  if (!ours.has(L.hooks)) U.backup(L.hooks)
  U.writeText(L.hooks, JSON.stringify(doc, null, 2) + '\n')
  return true
}

// Only ever delete a directory we can prove is ours.
function removeSkill (L) {
  const skillFile = path.join(L.skillDir, 'SKILL.md')
  if (!fs.existsSync(skillFile)) return false
  if (!U.readText(skillFile).includes('name: iriscale-voice')) return false
  const resolved = fs.realpathSync(L.skillDir)
  if (!resolved.startsWith(fs.realpathSync(L.home) + path.sep)) {
    U.die(`refusing to remove unexpected skill directory: ${resolved}`)
  }
  fs.rmSync(resolved, { recursive: true, force: true })
  return true
}

function uninstall (argv) {
  const L = paths()
  const marker = core.readMarker()
  const record = (marker && marker.agents && marker.agents.codex) || {}
  const ours = new Set(record.created || [])
  const removed = []

  const notifyResult = unmergeNotify(L, ours, record.replacedNotify)
  if (notifyResult) removed.push(typeof notifyResult === 'string' ? notifyResult : 'config.toml notify')
  if (unmergeHooks(L, ours)) removed.push('hooks.json hooks')
  if (removeSkill(L)) removed.push('Codex skill')
  removed.push(...core.returnCreated(record.created || []))

  // "config.toml notify, ..., config.toml" reads oddly: deleting the file supersedes
  // having stripped a line from it.
  const superseded = { 'config.toml': 'config.toml notify', 'hooks.json': 'hooks.json hooks' }
  let summary = removed.filter(r => !Object.entries(superseded)
    .some(([file, line]) => r === line && removed.includes(file)))

  const { removedShared, last } = core.forgetAgent(L, 'codex')
  summary = summary.concat(removedShared)
  console.log(summary.length
    ? `Iriscale Voice uninstalled for ${LABEL} (${summary.join(', ')}). Restart Codex and your terminal.`
    : `Nothing to uninstall - no ${LABEL} configuration found.`)
  // Only once everything is gone is there anything left for npm to remove.
  if (last) {
    core.reportLeftovers()
    console.log('Installed with npm as well? Finish with: npm uninstall -g @iriscale/voice')
  }
  return 0
}

// What --apply would write, for people who would rather paste it themselves.
function plan () {
  const L = paths()
  const lines = []
  lines.push('# At the TOP of ~/.codex/config.toml (notify is a top-level key):')
  lines.push(notifyLine(L))
  lines.push('')
  lines.push('# ~/.codex/hooks.json - in /hooks verify Installed=1, then trust each:')
  const hooks = {}
  for (const { event, arg, timeout } of HOOK_EVENTS) hooks[event] = hookEntry(L, arg, timeout)
  lines.push(JSON.stringify({ hooks }, null, 2))
  return { layout: L, lines }
}

function doctor () {
  const L = paths()
  let failed = false
  const bad = message => { failed = true; console.log(`  ERROR ${message}`) }
  console.log('Codex voice configuration')
  try {
    const lines = U.readText(L.config).split(/\r?\n/)
    const span = findTopLevelNotify(lines)
    if (!span || lines.slice(span[0], span[1] + 1).join('\n').trim() !== notifyLine(L)) {
      bad('notify differs from this installation; reapply install codex --apply to restore its target')
    } else console.log('  OK    completion notify points at this installation')
  } catch (err) { bad(`cannot verify ${L.config}: ${err.message}`) }
  try {
    const doc = JSON.parse(U.readText(L.hooks))
    for (const { event, arg } of HOOK_EVENTS) {
      const groups = doc && doc.hooks && doc.hooks[event]
      const handlers = Array.isArray(groups) ? groups.flatMap(g => g && Array.isArray(g.hooks) ? g.hooks : []) : []
      const expected = hookCommand(L, arg)
      const matches = handlers.filter(h => h && h.type === 'command' && h.command === expected &&
        (!U.isWindows || !h.commandWindows || h.commandWindows === expected))
      if (matches.length !== 1) bad(`${event}: expected exactly one handler pointing at ${L.launcher}`)
      else console.log(`  OK    ${event} handler is configured`)
    }
  } catch (err) { bad(`cannot verify ${L.hooks}: ${err.message}`) }
  for (const target of new Set([L.script, L.launcher])) {
    try { fs.accessSync(target, fs.constants.X_OK) } catch { bad(`missing or non-executable hook target: ${target}`) }
  }
  const stale = core.driftWarning()
  if (stale) bad(stale)
  console.log('  CHECK Restart Codex; open /hooks and confirm these handlers are installed and trusted.')
  console.log('  CHECK Run iriscale-voice test to check the speech backend; file checks cannot confirm audible output.')
  console.log('  NOTE  PostToolUse clears an answered permission after the tool finishes; approval alone is not a prompt.')
  return failed ? 1 : 0
}

module.exports = { install, uninstall, plan, doctor, LABEL }
