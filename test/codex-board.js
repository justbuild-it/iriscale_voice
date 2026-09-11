'use strict'

// Exercise installed lifecycle commands through the host shell, just as Codex does.
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
  assert.ok(!/^notify = .*iriscale-voice/m.test(config), 'internal Codex requests must not reach voice through legacy notify')
  const hooks = JSON.parse(fs.readFileSync(path.join(env.CODEX_HOME, 'hooks.json'), 'utf8')).hooks
  const invokeHook = (event, payload) => {
    const command = hooks[event][0].hooks[0]
    assert.ok(command, `missing ${event} handler`)
    if (U.isWindows) {
      const r = spawnSync(process.env.COMSPEC || 'cmd.exe', ['/d', '/s', '/c', `"${command.commandWindows}"`],
        { env, input: JSON.stringify(payload), encoding: 'utf8', windowsVerbatimArguments: true, timeout: 60000 })
      assert.equal(r.status, 0, r.stdout + r.stderr)
      return r.stdout
    }
    return run('sh', ['-c', command.command], JSON.stringify(payload))
  }
  const index = path.join(env.CODEX_HOME, 'session_index.jsonl')
  const stateFile = path.join(env.CLAUDE_CONFIG_DIR, 'iriscale-voice-sessions/probe')
  const cwd = 'C:\\Users\\deang\\projects\\iriscale_voice'
  const notify = () => invokeHook('Stop', { session_id: 'probe', hook_event_name: 'Stop', cwd,
    last_assistant_message: 'Quotes " and apostrophes \' and $() remain data' })
  const state = () => fs.readFileSync(stateFile, 'utf8')
  const internal = JSON.stringify({ type: 'agent-turn-complete', 'thread-id': 'internal-temporary', cwd })
  assert.equal(run(shell, [script, 'notify', internal]), '')
  assert.equal(run(shell, [script, 'notify-stdin'], internal), '')
  assert.equal(fs.existsSync(path.join(env.CLAUDE_CONFIG_DIR, 'iriscale-voice-sessions/internal-temporary')), false)
  console.log('ok: internal legacy notifications create neither output nor a board row')
  assert.equal(notify(), '', 'Stop must leave stdout empty even in debug mode')
  assert.ok(state().includes('name=iriscale_voice\n'), state())
  assert.ok(state().includes(`cwd=${cwd}\n`), state())
  console.log('ok: installed Stop hook preserves Windows path and project-folder fallback')

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
  invokeHook('Stop', { session_id: 'second-user', hook_event_name: 'Stop', cwd })
  assert.ok(fs.existsSync(stateFile))
  assert.ok(fs.existsSync(path.join(env.CLAUDE_CONFIG_DIR, 'iriscale-voice-sessions/second-user')))
  invokeHook('SessionEnd', { session_id: 'probe', hook_event_name: 'SessionEnd', cwd })
  assert.equal(fs.existsSync(stateFile), false, 'ended session was retained')
  assert.ok(fs.existsSync(path.join(env.CLAUDE_CONFIG_DIR, 'iriscale-voice-sessions/second-user')), 'cleanup removed a different session sharing the folder')
  console.log('ok: two real sessions sharing a folder remain distinct; SessionEnd removes only its own row')
} finally {
  fs.rmSync(root, { recursive: true, force: true })
}
