'use strict'
const assert = require('assert/strict')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const U = require('../npm/util')
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'iriscale-passive-'))
const sessions = path.join(root, 'iriscale-voice-sessions')
const runtime = path.join(root, 'iriscale-voice-runtime')
const env = { ...process.env, CLAUDE_CONFIG_DIR: root, CODEX_HOME: root, IRISCALE_VOICE_DEBUG: '1' }
const script = path.resolve(__dirname, '../bin/iriscale-voice')
function run (args, input) {
  const r = spawnSync(U.isWindows ? U.gitBash() : 'sh', [script, ...args], { env, input, encoding: 'utf8', timeout: 10000 })
  assert.equal(r.error, undefined)
  assert.equal(r.status, 0, r.stdout + r.stderr)
  return r.stdout + r.stderr
}
function hook (event) { return run(['codex-' + event], JSON.stringify({ session_id: 'probe', cwd: '/work/voice' })) }
function state () { return fs.readFileSync(path.join(sessions, 'probe'), 'utf8') }
try {
  fs.writeFileSync(path.join(root, 'iriscale-voice.conf'), 'min_turn_seconds=0\nrepeat_cooldown=0\n')
  hook('stamp')
  assert.match(state(), /status=working/)
  assert.match(hook('Stop'), /SPEAK \[Stop\].*done/)
  assert.match(state(), /status=done/)
  assert.doesNotMatch(state(), /remind_at=\d/)
  assert.match(run(['sessions', '--keys', '--plain']), /voice\s+DONE/)
  assert.doesNotMatch(run(['tick', 'probe']), /still ready for review/)
  console.log('ok: Codex completion speaks, shows DONE, and schedules no review reminder')
  const old = state().replace('status=done', 'status=ready') + 'remind_at=1\n'
  fs.writeFileSync(path.join(sessions, 'probe'), old)
  assert.match(run(['sessions', '--plain']), /voice\s+DONE/)
  assert.doesNotMatch(run(['tick', 'probe']), /still ready for review/)
  assert.match(state(), /status=done/)
  assert.match(state(), /remind_at=\n/)
  console.log('ok: legacy Codex READY rows display DONE and retire old review reminders')
  fs.writeFileSync(path.join(runtime, 'last_prompt'), '1\n')
  assert.doesNotMatch(run(['stamp'], JSON.stringify({ session_id: 'other', cwd: '/work/other' })), /welcome_back: would say/)
  hook('stamp')
  assert.match(state(), /status=working/)
  assert.doesNotMatch(run(['--help']), /review <name|mark reviewed/)
  console.log('ok: finished Codex rows are absent from review summaries; prompts resume work')
} finally {
  fs.rmSync(root, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
}
