'use strict'

// Locate a top-level assignment without interpreting or reserializing other TOML.
// Strings (including multiline/literal strings) and comments do not balance arrays.
// An uncertain boundary is an error, never permission to consume the rest of a file.
function findTopLevelNotify (lines) {
  let found = null
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*(#.*)?$/.test(lines[i])) continue
    if (/^\s*\[/.test(lines[i])) break
    const assignment = lines[i].match(/^\s*([^=]+?)\s*=/)
    if (!assignment) throw new Error(`Cannot safely edit config.toml: expected an assignment at line ${i + 1}`)
    let key = assignment[1].trim()
    if (key.startsWith('"')) {
      key = JSON.parse(key.replace(/\\U([0-9a-fA-F]{8})/g,
        (_, hex) => JSON.stringify(String.fromCodePoint(parseInt(hex, 16))).slice(1, -1)))
    } else if (key.startsWith("'")) key = key.slice(1, -1)
    const start = i
    let quote = ''
    let triple = false
    let escaped = false
    let stack = ''
    let value = false
    let complete = false
    for (; i < lines.length; i++) {
      const line = lines[i]
      for (let c = i === start ? assignment[0].length : 0; c < line.length; c++) {
        const ch = line[c]
        if (quote) {
          if (escaped) { escaped = false; continue }
          if (quote === '"' && ch === '\\') { escaped = true; continue }
          if (ch === quote) {
            if (!triple) quote = ''
            else if (line.slice(c, c + 3) === quote.repeat(3)) {
              // TOML allows one or two quotes immediately before the closing triple.
              let n = 3
              while (n < 5 && line[c + n] === quote) n++
              c += n - 1; quote = ''
            }
          }
          continue
        }
        if (ch === '#') break
        if (/\s/.test(ch)) continue
        value = true
        if (ch === '"' || ch === "'") {
          quote = ch; triple = line.slice(c, c + 3) === ch.repeat(3)
          if (triple) c += 2
        } else if (ch === '[' || ch === '{') stack += ch
        else if (ch === ']' || ch === '}') {
          if (stack.slice(-1) !== (ch === ']' ? '[' : '{')) throw new Error('Cannot safely edit config.toml: unbalanced value')
          stack = stack.slice(0, -1)
        }
      }
      if (quote && !triple) throw new Error('Cannot safely edit config.toml: unfinished string')
      escaped = false
      if (!quote && !stack) { complete = value; break }
    }
    if (!complete) throw new Error('Cannot safely edit config.toml: unfinished value')
    if (key === 'notify') {
      if (found) throw new Error('Cannot safely edit config.toml: duplicate notify')
      found = [start, i]
    }
  }
  return found
}

module.exports = { findTopLevelNotify }
