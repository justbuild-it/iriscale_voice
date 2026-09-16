'use strict'
const assert = require('assert/strict')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const U = require('../npm/util')
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'iriscale-claude-review-'))
const env = { ...process.env, CLAUDE_CONFIG_DIR: root, CODEX_HOME: root, IRISCALE_VOICE_DEBUG: '1' }
const script = path.resolve(__dirname, '../bin/iriscale-voice')
const statePath = path.join(root, 'iriscale-voice-sessions/sales')
function run (args, input) {
  const r = spawnSync(U.isWindows ? U.gitBash() : 'sh', [script, ...args], { env, input, encoding: 'utf8', timeout: 10000 })
  assert.equal(r.error, undefined)
  assert.equal(r.status, 0, r.stdout + r.stderr)
  return r.stdout + r.stderr
}
const hook = (event, id = 'sales') => run([event], JSON.stringify({ session_id: id, cwd: '/work/sales_ai_visibility', hook_event_name: event }))
const state = () => fs.readFileSync(statePath, 'utf8')
function due () { fs.writeFileSync(statePath, state().replace(/^remind_at=.*$/m, 'remind_at=1')) }
try {
  fs.writeFileSync(path.join(root, 'iriscale-voice.conf'), 'min_turn_seconds=0\nrepeat_cooldown=0\nremind_pause=0\n')
  hook('stamp')
  assert.match(hook('Stop'), /SPEAK \[Stop\]/)
  assert.match(hook('idle_prompt'), /SPEAK \[idle_prompt\]/)
  assert.doesNotMatch(state(), /remind_at=\d/)
  due() // a persisted schedule from a previous release must not emit once more
  assert.doesNotMatch(run(['tick', 'sales']), /SPEAK/)
  assert.doesNotMatch(state(), /remind_at=\d/)
  fs.writeFileSync(path.join(root, 'iriscale-voice-runtime/last_prompt'), '1\n')
  assert.doesNotMatch(hook('stamp', 'other'), /while you were away/)
  console.log('ok: initial Claude alerts remain; stale review schedules and summaries stay quiet')
  for (const event of ['PermissionRequest', 'StopFailure']) {
    hook(event); due()
    assert.match(run(['tick', 'sales']), /SPEAK \[Remind\]/)
  }
  console.log('ok: pending permission and error reminders still work')
  run(['config', 'set', 'remind_review', '5'])
  hook('stamp'); hook('Stop'); hook('idle_prompt'); due()
  assert.match(run(['tick', 'sales']), /SPEAK \[Remind\]/)
  run(['config', 'set', 'remind_review', 'off']); due()
  assert.doesNotMatch(run(['tick', 'sales']), /SPEAK/)
  console.log('ok: explicit review reminders remain opt-in; disabling cancels existing schedules')
} finally {
  fs.rmSync(root, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
}
