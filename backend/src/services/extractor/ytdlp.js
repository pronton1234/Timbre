// Primary extractor: yt-dlp subprocess with bgutil PO-token sidecar + deno JS runtime.
// Cookies file required (datacenter IPs are rejected without a logged-in session).
//
// Env:
//   YTDLP_BIN          path to yt-dlp binary (default: yt-dlp)
//   YTDLP_COOKIES      path to Netscape-format cookies.txt (required)
//   BGUTIL_BASE_URL    bgutil HTTP sidecar (default: http://127.0.0.1:4416)
//   YTDLP_CLIENTS      comma-sep player clients (default: web,mweb)
//   YTDLP_CACHE_DIR    persistent cache dir (default: $HOME/.cache/yt-dlp)
//   YTDLP_WARMUP_ID    videoId to pre-warm on init (default: dQw4w9WgXcQ)

import { spawn } from 'node:child_process'
import { homedir } from 'node:os'
import path from 'node:path'

const YTDLP_BIN = process.env.YTDLP_BIN || 'yt-dlp'
const COOKIES = process.env.YTDLP_COOKIES
const BGUTIL = process.env.BGUTIL_BASE_URL || 'http://127.0.0.1:4416'
const CLIENTS = process.env.YTDLP_CLIENTS || 'web,mweb'
const CACHE_DIR = process.env.YTDLP_CACHE_DIR || path.join(homedir(), '.cache', 'yt-dlp')
const WARMUP_ID = process.env.YTDLP_WARMUP_ID || 'dQw4w9WgXcQ'

// Passing HOME + XDG_CACHE_HOME explicitly ensures the EJS scripts and signature
// function cache survive service restarts (systemd otherwise gives an empty HOME).
function spawnEnv() {
  return {
    ...process.env,
    HOME: homedir(),
    XDG_CACHE_HOME: path.dirname(CACHE_DIR),
  }
}

function run(args, { timeoutMs = 20_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(YTDLP_BIN, args, { stdio: ['ignore', 'pipe', 'pipe'], env: spawnEnv() })
    let stdout = ''
    let stderr = ''
    const t = setTimeout(() => {
      child.kill('SIGKILL')
      reject(new Error(`yt-dlp timeout after ${timeoutMs}ms`))
    }, timeoutMs)
    child.stdout.on('data', d => { stdout += d.toString() })
    child.stderr.on('data', d => { stderr += d.toString() })
    child.on('error', e => { clearTimeout(t); reject(e) })
    child.on('close', code => {
      clearTimeout(t)
      if (code !== 0) {
        const tail = stderr.trim().split('\n').slice(-3).join(' | ')
        return reject(new Error(`yt-dlp exit ${code}: ${tail}`))
      }
      resolve({ stdout, stderr })
    })
  })
}

function extractArgs(videoId) {
  return [
    '--cookies', COOKIES,
    '--cache-dir', CACHE_DIR,
    '--remote-components', 'ejs:github',
    '--extractor-args', `youtube:player_client=${CLIENTS};youtubepot-bgutilhttp:base_url=${BGUTIL}`,
    '-f', 'bestaudio[ext=m4a]/bestaudio',
    '-g',
    '--quiet',
    '--no-warnings',
    '--no-progress',
    '--no-playlist',
    `https://youtu.be/${videoId}`,
  ]
}

export async function getStreamUrl(videoId) {
  if (!COOKIES) throw new Error('YTDLP_COOKIES not set')
  const { stdout } = await run(extractArgs(videoId))
  const url = stdout.trim().split('\n').filter(Boolean).pop()
  if (!url || !/^https:\/\/.*googlevideo\.com\/videoplayback/.test(url)) {
    throw new Error(`yt-dlp: unexpected stdout: ${stdout.slice(0, 200)}`)
  }
  return url
}

// Pre-warm on boot so the first real /resolve doesn't pay the EJS-download and
// sig-func-compile cost. Silent on any failure (first call will retry).
export async function init() {
  if (!COOKIES) return
  try {
    await run(extractArgs(WARMUP_ID), { timeoutMs: 30_000 })
  } catch (_e) {
    // swallow: warmup is best-effort
  }
}

// Exposed for unit tests that want to stub the subprocess.
export const _internal = { run, extractArgs }
