'use strict'
const assert = require('assert/strict')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const U = require('../npm/util')
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'iriscale-review-'))
const sessions = path.join(root, 'iriscale-voice-sessions')
fs.mkdirSync(sessions)
const env = { ...process.env, CLAUDE_CONFIG_DIR: root, CODEX_HOME: root, IRISCALE_VOICE_DEBUG: '1' }
const script = path.resolve(__dirname, '../bin/iriscale-voice')
function run (...args) {
  const r = spawnSync(U.isWindows ? U.gitBash() : 'sh', [script, ...args], { env, encoding: 'utf8', timeout: 10000 })
  assert.equal(r.error, undefined)
  return r
}
function row (id, name, status = 'ready', since = 100) {
  fs.writeFileSync(path.join(sessions, id), `agent=codex\nname=${name}\nstatus=${status}\nsince=${since}\nupdated=${Math.floor(Date.now() / 1000)}\npid=\nsaid=${name} done\nnote=\nreminded=0\nremind_at=101\n`)
}
function state (id) { return fs.readFileSync(path.join(sessions, id), 'utf8') }
try {
  row('one', 'voice.codex')
  assert.equal(run('review', 'voice.codex').status, 0)
  assert.match(state('one'), /status=reviewed/)
  assert.match(state('one'), /remind_at=\n/)
  assert.match(state('one'), /said=voice.codex done/)
  assert.doesNotMatch(run('tick', 'one').stdout, /still ready for review/)
  console.log('ok: review retains the row and last announcement, and stops reminders')
  for (const status of ['working', 'blocked', 'error', 'scheduled']) {
    row('one', 'voice.codex', status)
    assert.notEqual(run('review', 'voice.codex').status, 0)
    assert.match(state('one'), new RegExp(`status=${status}`))
  }
  console.log('ok: review cannot dismiss work or a pending action')
  row('one', 'shared'); row('two', 'shared')
  assert.notEqual(run('review', 'shared').status, 0)
  assert.match(state('one'), /status=ready/)
  assert.equal(run('review', 'one').status, 0)
  assert.match(state('two'), /status=ready/)
  fs.writeFileSync(path.join(root, 'session_index.jsonl'), JSON.stringify({ id: 'two', thread_name: 'renamed' }) + '\n')
  assert.equal(run('review', 'renamed').status, 0)
  console.log('ok: duplicate names require an ID; current Codex names are accepted')
  row('one', 'voice.codex', 'ready', 200)
  fs.unlinkSync(path.join(sessions, 'two'))
  assert.equal(run('sessions', '--keys', '--plain').status, 0)
  assert.equal(run('review-row', '1').status, 0)
  row('one', 'voice.codex', 'ready', 201)
  assert.notEqual(run('review-row', '1').status, 0)
  assert.match(state('one'), /status=ready/)
  assert.notEqual(run('review', '../outside').status, 0)
  fs.writeFileSync(path.join(root, 'session_index.jsonl'), JSON.stringify({ id: 'one', thread_name: 'caf\u00e9|split\nsecond line' }) + '\n')
  assert.equal(run('sessions', '--keys', '--plain').status, 0)
  const map = fs.readFileSync(path.join(root, 'iriscale-voice-runtime/board.rows'), 'utf8').trim().split('\n')
  assert.equal(map.length, 1)
  assert.equal(map[0].split('|')[4], 'one')
  assert.equal(run('review-row', '1').status, 0)
  console.log('ok: board review targets the displayed completion, rejecting stale rows')
} finally {
  fs.rmSync(root, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
}
