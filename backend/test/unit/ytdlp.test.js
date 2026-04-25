// Unit tests for the yt-dlp subprocess wrapper.
// We stub out YTDLP_BIN by pointing it at a small inline Node script that mimics
// yt-dlp's stdout/exit-code contract, so no real yt-dlp install is required.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { writeFileSync, mkdtempSync, chmodSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'

const tmp = mkdtempSync(path.join(tmpdir(), 'ytdlp-test-'))
const cookies = path.join(tmp, 'cookies.txt')
writeFileSync(cookies, '# Netscape HTTP Cookie File\n', 'utf8')
process.env.YTDLP_COOKIES = cookies

function writeFakeBin(body) {
  const p = path.join(tmp, `fake-${Math.random().toString(36).slice(2)}.mjs`)
  writeFileSync(p, `#!/usr/bin/env node\n${body}\n`, 'utf8')
  chmodSync(p, 0o755)
  return p
}

test('getStreamUrl returns the googlevideo URL on success', async () => {
  const good = 'https://rr4---sn-test.googlevideo.com/videoplayback?x=1'
  process.env.YTDLP_BIN = writeFakeBin(`process.stdout.write(${JSON.stringify(good + '\n')}); process.exit(0)`)
  const mod = await import(`../../src/services/extractor/ytdlp.js?cachebust=${Math.random()}`)
  const url = await mod.getStreamUrl('dQw4w9WgXcQ')
  assert.equal(url, good)
})

test('getStreamUrl throws when yt-dlp exits non-zero', async () => {
  process.env.YTDLP_BIN = writeFakeBin(`process.stderr.write('ERROR: Sign in to confirm'); process.exit(1)`)
  const mod = await import(`../../src/services/extractor/ytdlp.js?cachebust=${Math.random()}`)
  await assert.rejects(mod.getStreamUrl('abc'), /yt-dlp exit 1/)
})

test('getStreamUrl throws when stdout is not a googlevideo URL', async () => {
  process.env.YTDLP_BIN = writeFakeBin(`process.stdout.write('https://example.com/not-youtube\\n'); process.exit(0)`)
  const mod = await import(`../../src/services/extractor/ytdlp.js?cachebust=${Math.random()}`)
  await assert.rejects(mod.getStreamUrl('abc'), /unexpected stdout/)
})

test('getStreamUrl throws when cookies env var is missing', async () => {
  const saved = process.env.YTDLP_COOKIES
  delete process.env.YTDLP_COOKIES
  process.env.YTDLP_BIN = writeFakeBin(`process.exit(0)`)
  try {
    const mod = await import(`../../src/services/extractor/ytdlp.js?cachebust=${Math.random()}`)
    await assert.rejects(mod.getStreamUrl('abc'), /YTDLP_COOKIES not set/)
  } finally {
    process.env.YTDLP_COOKIES = saved
  }
})

test('subprocess is killed after timeout', async () => {
  // Fake bin hangs forever. The wrapper's default timeout is 20s, so we
  // shorten it by re-importing and calling _internal.run directly.
  process.env.YTDLP_BIN = writeFakeBin(`setInterval(() => {}, 1000)`)
  const mod = await import(`../../src/services/extractor/ytdlp.js?cachebust=${Math.random()}`)
  await assert.rejects(mod._internal.run(['--version'], { timeoutMs: 200 }), /timeout/)
})
