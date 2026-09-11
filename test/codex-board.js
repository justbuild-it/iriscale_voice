'use strict'

// Exercise the installed notify command with native argv, just as Codex does.
const fs = require('fs')
const os = require('os')
const path = require('path')
const assert = require('assert/strict')
const { spawnSync } = require('child_process')
const U = require('../npm/util')
const repo = path.resolve(__dirname, '..')
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'iriscale-board-'))
const home = path.join(root, "O'Neil caf\u00e9")
const install = path.join(home, 'iriscale-voice')
const env = { ...process.env, HOME: home, USERPROFILE: home,
  IRISCALE_VOICE_INSTALL_ROOT: install, CLAUDE_CONFIG_DIR: path.join(home, 'claude'),
  CODEX_HOME: path.join(home, 'codex'), IRISCALE_VOICE_DEBUG: '1' }
fs.mkdirSync(env.CLAUDE_CONFIG_DIR, { recursive: true })
fs.mkdirSync(env.CODEX_HOME)
const shell = U.isWindows ? U.gitBash() : 'sh'
function run (file, args, input) {
  const r = spawnSync(file, args, { env, input, encoding: 'utf8', timeout: 60000 })
  assert.equal(r.error, undefined, String(r.error))
  assert.equal(r.status, 0, r.stdout + r.stderr)
  return r.stdout
}
try {
  if (process.argv.includes('--powershell')) {
    run('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
      path.join(repo, 'install.ps1'), '-SourcePath', repo, '-InstallRoot', install,
      '-CodexHome', env.CODEX_HOME, '-SkipPath', '-SkipProfile'])
  } else {
    run(process.execPath, [path.join(repo, 'npm/cli.js'), 'install', 'codex', '--apply', '--skip-path'])
  }
  const script = path.join(install, 'bin/iriscale-voice')
  const config = fs.readFileSync(path.join(env.CODEX_HOME, 'config.toml'), 'utf8')
  const command = JSON.parse(config.match(/^notify = (.+)$/m)[1])
  const index = path.join(env.CODEX_HOME, 'session_index.jsonl')
  const stateFile = path.join(env.CLAUDE_CONFIG_DIR, 'iriscale-voice-sessions/probe')
  const cwd = 'C:\\Users\\deang\\projects\\iriscale_voice'
  const notify = () => run(command[0], [...command.slice(1), JSON.stringify({
    type: 'agent-turn-complete', 'thread-id': 'probe', cwd,
    'last-assistant-message': 'Quotes " and apostrophes \' and $() remain data'
  })])
  const state = () => fs.readFileSync(stateFile, 'utf8')
  notify()
  assert.ok(state().includes('name=iriscale_voice\n'), state())
  assert.ok(state().includes(`cwd=${cwd}\n`), state())
  console.log('ok: native notify preserves Windows path and project-folder fallback')

  fs.writeFileSync(index, JSON.stringify({ id: 'probe', thread_name: 'Old title' }) + '\n' +
    '{ "id" : "probe", "thread_name" : "Renamed session" }\n' +
    JSON.stringify({ id: 'probe-other', thread_name: 'Wrong session' }))
  notify()
  assert.ok(state().includes('name=Renamed session\n'), state())
  console.log('ok: latest matching title wins, including spaced JSON and no final newline')

  fs.appendFileSync(index, '\n' + JSON.stringify({ id: 'probe', thread_name: 'New board title' }))
  const before = state()
  const board = run(shell, [script, 'sessions', '--plain'])
  assert.ok(board.includes('New board title'), board)
  assert.equal(state(), before, 'rendering must not change session lifecycle timestamps')
  console.log('ok: board reflects rename without another hook event')
  assert.match(run(shell, [script, 'forget', 'New board title']), /forgot 1 session/)
  assert.equal(fs.existsSync(stateFile), false)
  console.log('ok: forget accepts the currently displayed name')

  fs.unlinkSync(index)
  run(shell, [script, 'codex-stamp'], JSON.stringify({ session_id: 'probe', hook_event_name: 'UserPromptSubmit', cwd }))
  assert.ok(state().includes('agent=codex\n'), state())
  assert.ok(state().includes('name=iriscale_voice\n'), state())
  assert.ok(state().includes('status=working\n'), state())
  console.log('ok: unnamed Codex hook stays identified as Codex')
} finally {
  fs.rmSync(root, { recursive: true, force: true })
}
