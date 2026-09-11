'use strict'

// End-to-end preservation checks. No global installs, user PATH changes, or network.
const fs = require('fs')
const os = require('os')
const path = require('path')
const assert = require('assert/strict')
const { spawnSync } = require('child_process')
const repo = path.resolve(__dirname, '..')
const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'iriscale-audit-'))
let failures = 0
let passed = 0
const ps = process.argv.includes('--powershell')

function fixture (name) {
  const dir = path.join(sandbox, name)
  const home = path.join(dir, 'codex')
  const root = path.join(dir, 'iriscale-voice')
  fs.mkdirSync(home, { recursive: true })
  const env = { ...process.env, HOME: dir, USERPROFILE: dir, CODEX_HOME: home,
    CLAUDE_CONFIG_DIR: path.join(dir, 'claude'), IRISCALE_VOICE_INSTALL_ROOT: root,
    TMPDIR: dir, TMP: dir, TEMP: dir }
  const config = path.join(home, 'config.toml')
  const hooks = path.join(home, 'hooks.json')
  function run (verb = 'install', agent = 'codex', extra = []) {
    const args = ps
      ? ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', path.join(repo, 'install.ps1'),
          '-InstallRoot', root, '-CodexHome', home, '-SourcePath', repo, '-SkipPath', '-SkipProfile',
          ...(verb === 'uninstall' ? ['-Uninstall'] : [])]
      : [path.join(repo, 'npm', 'cli.js'), verb, ...(verb === 'update' ? [] : [agent, '--apply']), '--skip-path', ...extra]
    const r = spawnSync(ps ? 'powershell.exe' : process.execPath, args, { env, encoding: 'utf8', timeout: 60000 })
    assert.equal(r.error, undefined, String(r.error))
    return r
  }
  function success (...args) {
    const r = run(...args)
    assert.equal(r.status, 0, r.stdout + r.stderr)
    return r
  }
  return { home, root, env, config, hooks, run, success }
}
function test (name, fn) {
  try { fn(); passed++; console.log(`ok: ${name}`) }
  catch (e) { failures++; console.error(`FAIL: ${name}: ${e.message}`) }
}

const cases = [
  'notify = ["echo", "["]',
  'notify = ["echo", "]"] # [',
  'notify = [\n  "echo", # [\n  "hello"\n]',
  "'notify' = ['echo', '[']",
  '"notify" = ["echo", "hello"]',
  '"\\u006eotify" = ["echo", "escaped"]',
  '"\\U0000006eotify" = ["echo", "escaped"]',
  'Notify = ["echo", "different-key"]\nnotify = ["echo", "real"]',
  'description = """\nnotify = [\n[not_a_table]\n"""\nnotify = ["echo", "real"]'
]
for (const [i, original] of cases.entries()) test(`TOML round trip ${i}`, () => {
  const f = fixture(`toml-${i}`)
  const tail = '\nmodel = "keep-me"\n[projects.foo]\ntrust_level = "trusted"\nnotify = ["table-value"]\n'
  fs.writeFileSync(f.config, original + tail)
  f.success()
  assert.ok(fs.readFileSync(f.config, 'utf8').endsWith(tail), 'unrelated configuration changed')
  f.success()
  f.success('uninstall')
  assert.equal(fs.readFileSync(f.config, 'utf8'), original + tail)
})
test('unfinished notify is refused before any write', () => {
  const f = fixture('malformed')
  const original = 'notify = ["echo"\nmodel = "keep"\n'
  fs.writeFileSync(f.config, original)
  assert.notEqual(f.run().status, 0)
  assert.equal(fs.readFileSync(f.config, 'utf8'), original)
  assert.ok(!fs.existsSync(f.root), 'runtime was installed before validation')
})
test('mixed hook groups survive reinstall and uninstall', () => {
  const f = fixture('mixed')
  fs.writeFileSync(f.hooks, JSON.stringify({ hooks: { PermissionRequest: [{ matcher: 'Bash', hooks: [
    { type: 'command', command: 'echo my-policy Jos\u00e9 \u4e2d\u6587' },
    { type: 'command', command: 'sh /old/iriscale-voice PermissionRequest' }
  ] }] } }))
  f.success(); f.success()
  let d = JSON.parse(fs.readFileSync(f.hooks, 'utf8'))
  assert.ok(JSON.stringify(d).includes('echo my-policy'))
  assert.equal(d.hooks.PermissionRequest[0].matcher, 'Bash')
  assert.ok(d.hooks.PostToolUse, 'missing permission-resolved hook')
  f.success('uninstall')
  d = JSON.parse(fs.readFileSync(f.hooks, 'utf8'))
  assert.deepEqual(d.hooks.PermissionRequest, [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'echo my-policy Jos\u00e9 \u4e2d\u6587' }] }])
})
if (!ps) test('npx-style update reapplies the recorded homes', () => {
  const f = fixture('update')
  f.success()
  const script = path.join(f.root, 'bin', 'iriscale-voice')
  fs.writeFileSync(script, '# stale runtime\n')
  f.env.CODEX_HOME = path.join(sandbox, 'must-not-be-created')
  f.success('update')
    assert.ok(fs.readFileSync(script, 'utf8') === fs.readFileSync(path.join(repo, 'bin', 'iriscale-voice'), 'utf8'), 'stable runtime was not refreshed')
  assert.ok(!fs.existsSync(f.env.CODEX_HOME), 'update used the current home instead of the recorded home')
})
if (ps) test('Unicode install path runs the launcher', () => {
  const f = fixture('Jos\u00e9')
  f.success()
  assert.ok(fs.readFileSync(path.join(f.root, 'bin', 'iriscale-voice.cmd'), 'utf8').includes('%~dp0iriscale-voice'))
})
if (!ps) test('doctor checks real targets and accepts unrelated asynchronous hooks', () => {
  const f = fixture('doctor')
  f.success()
  const d = JSON.parse(fs.readFileSync(f.hooks, 'utf8'))
  d.hooks.SessionStart = [{ hooks: [{ type: 'command', command: 'echo custom', async: true }] }]
  fs.writeFileSync(f.hooks, JSON.stringify(d))
  f.success('doctor')
  d.hooks.PermissionRequest[0].hooks[0].command = 'echo missing-target'
  fs.writeFileSync(f.hooks, JSON.stringify(d))
  assert.notEqual(f.run('doctor').status, 0)
  f.success()
  fs.unlinkSync(path.join(f.root, 'bin', 'iriscale-voice'))
  assert.notEqual(f.run('doctor').status, 0)
})
if (!ps) test('Claude mixed hook groups keep sibling handlers', () => {
  const f = fixture('claude-mixed')
  const file = path.join(f.env.CLAUDE_CONFIG_DIR, 'settings.json')
  fs.mkdirSync(f.env.CLAUDE_CONFIG_DIR, { recursive: true })
  fs.writeFileSync(file, JSON.stringify({ hooks: { Stop: [{ hooks: [
    { type: 'command', command: 'echo custom' }, { type: 'command', command: 'sh /old/iriscale-voice Stop' }
  ] }] } }))
  f.success('install', 'claude'); f.success('install', 'claude'); f.success('uninstall', 'claude')
  assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')).hooks.Stop, [{ hooks: [{ type: 'command', command: 'echo custom' }] }])
})
// Only remove the unique directory this harness created.
assert.ok(sandbox.startsWith(path.join(os.tmpdir(), 'iriscale-audit-')))
fs.rmSync(sandbox, { recursive: true, force: true })
console.log(`audit installer (${ps ? 'PowerShell' : 'npm'}): ${passed} passed, ${failures} failed`)
process.exitCode = failures ? 1 : 0
