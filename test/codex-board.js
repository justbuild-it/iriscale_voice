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
  CODEX_HOME: path.join(home, 'codex'), TEMP: path.join(root, 'temp'), TMP: path.join(root, 'temp'), IRISCALE_VOICE_DEBUG: '1' }
fs.mkdirSync(env.TEMP)
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
      const powerShell = process.argv.includes('--hook-powershell')
      const r = spawnSync(powerShell ? 'powershell.exe' : (process.env.COMSPEC || 'cmd.exe'),
        powerShell ? ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Restricted', '-Command', command.commandWindows]
          : ['/d', '/s', '/c', `"${command.commandWindows}"`],
        { env, input: JSON.stringify(payload), encoding: 'utf8', windowsVerbatimArguments: !powerShell, timeout: command.timeout * 1000 })
      assert.equal(r.error, undefined, `${event}: ${r.error}`)
      assert.equal(r.status, 0, r.stdout + r.stderr)
      return r.stdout
    }
    return run('sh', ['-c', command.command], JSON.stringify(payload))
  }
  const index = path.join(env.CODEX_HOME, 'session_index.jsonl')
  if (U.isWindows && process.argv.includes('--hook-powershell')) {
    const plan = run(shell, [script, 'install', 'codex'])
    const manual = JSON.parse(plan.slice(plan.indexOf('{'), plan.lastIndexOf('}') + 1)).hooks
    for (const event of ['UserPromptSubmit', 'SessionEnd']) {
      const installed = hooks[event]
      hooks[event] = manual[event]
      assert.equal(invokeHook(event, { session_id: 'manual-probe', cwd: 'C:\\work', hook_event_name: event }), '')
      hooks[event] = installed
    }
    console.log('ok: manual Windows hook plan executes through PowerShell')
  }
  const stateFile = path.join(env.CLAUDE_CONFIG_DIR, 'iriscale-voice-sessions/probe')
  const cwd = 'C:\\Users\\deang\\projects\\iriscale_voice'
  const notify = () => invokeHook('Stop', { session_id: 'probe', hook_event_name: 'Stop', cwd,
    last_assistant_message: 'Quotes " and apostrophes \' and $() remain data' })
  const state = () => fs.readFileSync(stateFile, 'utf8')
  const internal = JSON.stringify({ type: 'agent-turn-complete', 'thread-id': 'internal-temporary', cwd })
  for (const event of ['UserPromptSubmit', 'PermissionRequest', 'PostToolUse']) {
    assert.equal(invokeHook(event, { session_id: 'probe', hook_event_name: event, cwd }), '',
      `${event} must leave stdout empty even in debug mode`)
  }
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
  if (U.isWindows) {
    // Debug mode skips the watcher that retained Codex's pipes in real sessions.
    env.IRISCALE_VOICE_DEBUG = ''
    fs.writeFileSync(path.join(env.CLAUDE_CONFIG_DIR, 'iriscale-voice.conf'), 'enabled=false\nboard_autostart=false\n')
    const permissionTranscript = path.join(root, 'permission.jsonl')
    fs.writeFileSync(permissionTranscript, JSON.stringify({ type: 'turn_context', payload: { turn_id: 'human-turn', approvals_reviewer: 'user' } }) + '\n')
    for (const event of ['Stop', 'PermissionRequest']) {
      const started = Date.now()
      assert.equal(invokeHook(event, { session_id: 'background-' + event, hook_event_name: event, cwd,
        turn_id: 'human-turn', transcript_path: permissionTranscript }), '')
      assert.ok(Date.now() - started < 5000, `${event} waited for its background watcher`)
      assert.equal(invokeHook('SessionEnd', { session_id: 'background-' + event }), '')
    }
    console.log('ok: non-debug hooks return while lifecycle watchers remain detached')
    const current = hooks.Stop[0].hooks[0].commandWindows
    const cached = `& '${path.join(install, 'bin/iriscale-voice.cmd').replace(/'/g, "''")}' codex-Stop; exit $LASTEXITCODE`
    hooks.Stop[0].hooks[0].commandWindows = 'powershell.exe -NoProfile -NonInteractive -EncodedCommand ' + Buffer.from(cached, 'utf16le').toString('base64')
    assert.equal(invokeHook('Stop', { session_id: 'cached-probe', cwd }), '')
    assert.equal(invokeHook('SessionEnd', { session_id: 'cached-probe' }), '')
    hooks.Stop[0].hooks[0].commandWindows = current
    console.log('ok: cached v0.1.30 launcher commands also use the isolated worker')
    assert.equal(fs.readdirSync(env.TEMP).filter(name => name.startsWith('iriscale-hook-')).length, 0, 'hook staging files were retained')
    fs.writeFileSync(script, '#!/bin/sh\ncat >/dev/null\n(sleep 4; printf survived > "$CLAUDE_CONFIG_DIR/worker-survived") </dev/null >/dev/null 2>&1 &\nexit 0\n')
    assert.equal(invokeHook('Stop', { session_id: 'survival-probe' }), '')
    const survivor = path.join(env.CLAUDE_CONFIG_DIR, 'worker-survived')
    const until = Date.now() + 6000
    while (!fs.existsSync(survivor) && Date.now() < until) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100)
    assert.equal(fs.readFileSync(survivor, 'utf8'), 'survived', 'background worker was killed when the hook completed')
    console.log('ok: background worker survives hook completion')
    fs.writeFileSync(script, '#!/bin/sh\nprintf \'{"continue":true}\\n\'\nprintf \'hook failure probe\\n\' >&2\nexit 7\n')
    const failure = spawnSync('powershell.exe', hooks.Stop[0].hooks[0].commandWindows.split(' ').slice(1),
      { env, input: '{}', encoding: 'utf8', timeout: 10000 })
    assert.equal(failure.error, undefined)
    assert.equal(failure.status, 7, failure.stderr)
    assert.equal(failure.stdout.trim(), '{"continue":true}')
    assert.match(failure.stderr, /hook failure probe/)
    console.log('ok: hook worker preserves failure status and output, and removes staging files')
    fs.writeFileSync(script, '#!/bin/sh\ncat >/dev/null\nsleep 20\n')
    const timedOut = spawnSync('powershell.exe', hooks.Stop[0].hooks[0].commandWindows.split(' ').slice(1),
      { env, input: '{}', encoding: 'utf8', timeout: 10000 })
    assert.equal(timedOut.error, undefined)
    assert.equal(timedOut.status, 1)
    assert.match(timedOut.stderr, /exceeded its execution limit/)
    assert.equal(fs.readdirSync(env.TEMP).filter(name => name.startsWith('iriscale-hook-')).length, 0)
    console.log('ok: stalled foreground hook returns an error and removes staging files')
  }
} finally {
  fs.rmSync(root, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
}
