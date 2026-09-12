'use strict'

const assert = require('assert/strict')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const U = require('../npm/util')
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'iriscale-permissions-'))
const transcript = path.join(root, 'rollout.jsonl')
const env = { ...process.env, CLAUDE_CONFIG_DIR: root, CODEX_HOME: root, IRISCALE_VOICE_DEBUG: '1' }
const script = path.resolve(__dirname, '../bin/iriscale-voice')
const state = path.join(root, 'iriscale-voice-sessions/probe')
const context = (reviewer, turn = 'turn-1') => JSON.stringify({ type: 'turn_context', payload: { turn_id: turn, approvals_reviewer: reviewer } }) + '\n'
function hook (event, extra = {}, agent = 'codex-') {
  const r = spawnSync(U.isWindows ? U.gitBash() : 'sh', [script, agent + event], {
    env, input: JSON.stringify({ session_id: 'probe', turn_id: 'turn-1', transcript_path: transcript, cwd: '/work/voice', ...extra }), encoding: 'utf8', timeout: 5000
  })
  assert.equal(r.error, undefined)
  assert.equal(r.status, 0, r.stderr)
  return r.stdout + r.stderr
}
try {
  fs.writeFileSync(transcript, context('auto_review'))
  hook('stamp')
  assert.doesNotMatch(hook('PermissionRequest'), /waiting for your answer/)
  assert.match(fs.readFileSync(state, 'utf8'), /status=working/)
  console.log('ok: automatic review does not announce or mark a session blocked')
  fs.writeFileSync(transcript, context('user', 'turn-2'))
  assert.match(hook('PermissionRequest', { turn_id: 'turn-2' }), /waiting for your answer/)
  assert.match(fs.readFileSync(state, 'utf8'), /status=blocked/)
  hook('resume')
  assert.match(fs.readFileSync(state, 'utf8'), /status=working/)
  assert.doesNotMatch(hook('PermissionRequest', { turn_id: 'turn-2', permission_mode: 'bypassPermissions' }), /waiting for your answer/)
  console.log('ok: verified human review still announces and resumes')
  fs.writeFileSync(transcript, context('auto_review', 'turn-3'))
  hook('stamp', { turn_id: 'turn-3' })
  fs.appendFileSync(transcript, JSON.stringify({ type: 'response_item', payload: 'x'.repeat(300000) }) + '\n')
  assert.doesNotMatch(hook('PermissionRequest', { turn_id: 'turn-3' }), /waiting for your answer/)
  assert.doesNotMatch(hook('PermissionRequest', { turn_id: 'unknown-turn' }), /waiting for your answer/)
  fs.writeFileSync(transcript, context('user', 'old-turn'))
  assert.doesNotMatch(hook('PermissionRequest', { turn_id: 'new-turn' }), /waiting for your answer/)
  fs.unlinkSync(transcript)
  assert.doesNotMatch(hook('PermissionRequest', { turn_id: 'missing' }), /waiting for your answer/)
  console.log('ok: current-turn cache survives long transcripts; unknown reviewers stay quiet')
  assert.match(hook('PermissionRequest', {}, ''), /waiting for your answer/)
  hook('resume')
  const lastPrompt = path.join(root, 'iriscale-voice-runtime/last_prompt')
  fs.writeFileSync(lastPrompt, '123\n')
  hook('PermissionRequest', { turn_id: 'missing' })
  assert.match(fs.readFileSync(state, 'utf8'), /status=working/)
  assert.match(fs.readFileSync(state, 'utf8'), /remind_at=\n/)
  assert.doesNotMatch(fs.readFileSync(state, 'utf8'), /waiting for your answer/)
  assert.equal(fs.readFileSync(lastPrompt, 'utf8'), '123\n', 'automatic review is not user presence')
  console.log('ok: Claude alerts remain; obsolete Codex blocked state and reminder are cleared')
  hook('SessionEnd')
  assert.equal(fs.existsSync(path.join(root, 'iriscale-voice-runtime/probe.codex-reviewer')), false)
} finally {
  fs.rmSync(root, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
}
