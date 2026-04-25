// Tests the extractor orchestrator: fallback chain + circuit breaker.
// We swap in fake extractor impls instead of using the real registry, because
// real extractors require network.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { _internal } from '../../src/services/extractor/index.js'

function makeFake(name, behavior) {
  let calls = 0
  return {
    name,
    breaker: _internal.makeBreaker(name),
    impl: {
      async getStreamUrl() {
        calls++
        const outcome = behavior[Math.min(calls - 1, behavior.length - 1)]
        if (outcome === 'throw') throw new Error(`${name} failed`)
        if (outcome === 'hang') return new Promise(() => {}) // never resolves
        if (typeof outcome === 'string') return outcome
        throw new Error('unknown outcome')
      },
    },
    _calls: () => calls,
  }
}

// Recreate the orchestrator loop locally so we can inject a fake registry.
async function extractStreamWith(registry, videoId) {
  let lastErr
  for (const ex of registry) {
    if (ex.breaker.isOpen()) continue
    try {
      const url = await _internal.withTimeout(ex.impl.getStreamUrl(videoId), 200)
      ex.breaker.recordSuccess()
      return { url, extractor: ex.name }
    } catch (e) {
      ex.breaker.recordFailure()
      lastErr = e
    }
  }
  throw lastErr ?? new Error('all failed')
}

test('primary succeeds → fallbacks not called', async () => {
  const primary = makeFake('primary', ['https://ok'])
  const secondary = makeFake('secondary', ['throw'])
  const chain = [primary, secondary]
  const { url, extractor } = await extractStreamWith(chain, 'v')
  assert.equal(url, 'https://ok')
  assert.equal(extractor, 'primary')
  assert.equal(secondary._calls(), 0)
})

test('primary throws → fallback used, chain reports fallback name', async () => {
  const primary = makeFake('primary', ['throw'])
  const secondary = makeFake('secondary', ['https://ok-2'])
  const { url, extractor } = await extractStreamWith([primary, secondary], 'v')
  assert.equal(url, 'https://ok-2')
  assert.equal(extractor, 'secondary')
})

test('all fail → error surfaces', async () => {
  const a = makeFake('a', ['throw'])
  const b = makeFake('b', ['throw'])
  const c = makeFake('c', ['throw'])
  await assert.rejects(extractStreamWith([a, b, c], 'v'))
})

test('circuit opens after 3 consecutive failures; closed primary is skipped', async () => {
  const primary = makeFake('primary', ['throw', 'throw', 'throw', 'https://would-succeed'])
  const secondary = makeFake('secondary', ['https://s1', 'https://s2', 'https://s3', 'https://s4'])
  const chain = [primary, secondary]

  // First 3 calls: primary throws each time, secondary answers
  for (let i = 0; i < 3; i++) {
    const { extractor } = await extractStreamWith(chain, 'v')
    assert.equal(extractor, 'secondary')
  }
  assert.equal(primary.breaker.isOpen(), true)

  // 4th call: primary circuit is open → impl not called, secondary answers
  const before = primary._calls()
  const { extractor } = await extractStreamWith(chain, 'v')
  assert.equal(extractor, 'secondary')
  assert.equal(primary._calls(), before, 'primary should have been skipped')
})

test('timeout triggers failure → circuit counter advances', async () => {
  const primary = makeFake('primary', ['hang', 'hang', 'hang'])
  const secondary = makeFake('secondary', ['https://s1', 'https://s2', 'https://s3'])
  const chain = [primary, secondary]
  for (let i = 0; i < 3; i++) await extractStreamWith(chain, 'v')
  assert.equal(primary.breaker.isOpen(), true)
})

test('success after failure resets consecutive counter', async () => {
  const primary = makeFake('primary', ['throw', 'throw', 'https://ok', 'throw'])
  const secondary = makeFake('secondary', ['https://s'])
  const chain = [primary, secondary]
  await extractStreamWith(chain, 'v') // fail → secondary
  await extractStreamWith(chain, 'v') // fail → secondary
  await extractStreamWith(chain, 'v') // primary ok, resets
  assert.equal(primary.breaker.isOpen(), false)
  // One more failure must not open circuit on its own
  await extractStreamWith(chain, 'v')
  assert.equal(primary.breaker.isOpen(), false)
})

test('withTimeout rejects on slow promise', async () => {
  await assert.rejects(_internal.withTimeout(new Promise(() => {}), 50), /timeout/)
})

test('withTimeout resolves fast promises', async () => {
  const v = await _internal.withTimeout(Promise.resolve(42), 100)
  assert.equal(v, 42)
})
