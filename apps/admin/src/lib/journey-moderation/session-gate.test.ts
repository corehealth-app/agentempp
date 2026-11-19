import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { createModerationSessionGate } from './session-watch'

const actor = '20000000-0000-4000-8000-000000000002'
const login = '20000000-0000-4000-a000-000000000002'
const context = {
  origin: 'https://admin.example.invalid',
  owner: '116234755b6d715da027f8def7c855b0379f43f61632186d08bcbbc9ec4bee87',
  login: 'deab31b7ba61be6560f34575ad01c5d143384ee600d8b29a945be3d9112613fe',
}
const hash = async (value: string) => createHash('sha256').update(value).digest('hex')
const session = (id = login) => ({
  user: { id: actor },
  access_token: `header.${Buffer.from(JSON.stringify({ sub: actor, session_id: id })).toString('base64url')}.signature`,
})
async function admitted() {
  const gate = createModerationSessionGate(context, hash)
  await new Promise<void>((resolve) => {
    gate.subscribe(() => {
      if (gate.snapshot === 'valid') resolve()
    })
    gate.handle(session())
  })
  return gate
}
describe('operational session admission and synchronous retirement', () => {
  it('does not admit before the initial asynchronous context proof', async () => {
    let release = () => {}
    const wait = new Promise<void>((r) => {
      release = r
    })
    const gate = createModerationSessionGate(context, async (value) => {
      await wait
      return hash(value)
    })
    const ready = new Promise<void>((r) =>
      gate.subscribe(() => {
        if (gate.snapshot === 'valid') r()
      }),
    )
    gate.handle(session())
    expect(gate.snapshot).toBe('checking')
    release()
    await ready
    expect(gate.snapshot).toBe('valid')
  })
  it('retires a different login synchronously before another digest can complete', async () => {
    const gate = await admitted()
    let retired = false
    gate.subscribe(() => {
      if (gate.snapshot === 'invalid') retired = true
    })
    gate.handle(session('20000000-0000-4000-a000-000000000003'))
    expect(gate.snapshot).toBe('invalid')
    expect(retired).toBe(true)
  })
  it('does not publish a late initial proof after a different user/login arrives', async () => {
    let release = () => {}
    const wait = new Promise<void>((r) => {
      release = r
    })
    const events: string[] = []
    const gate = createModerationSessionGate(context, async (value) => {
      await wait
      return hash(value)
    })
    gate.subscribe(() => {
      events.push(gate.snapshot)
    })
    gate.handle(session())
    gate.handle(session('20000000-0000-4000-a000-000000000003'))
    expect(gate.snapshot).toBe('invalid')
    release()
    await wait
    await hash('flush')
    await hash('flush again')
    expect(events).toEqual(['invalid'])
    expect(gate.snapshot).toBe('invalid')
  })
  it('retires logout immediately and never reopens from a later event', async () => {
    const gate = await admitted()
    gate.handle(null)
    expect(gate.snapshot).toBe('invalid')
    gate.handle(session())
    expect(gate.snapshot).toBe('invalid')
  })
  it('keeps the same original login across token refresh and disposes event publication', async () => {
    const gate = await admitted()
    const events: string[] = []
    const stop = gate.subscribe(() => {
      events.push(gate.snapshot)
    })
    gate.handle(session())
    expect(gate.snapshot).toBe('valid')
    stop()
    gate.close()
    gate.handle(session())
    expect(events).toEqual([])
    expect(gate.snapshot).toBe('invalid')
  })
})
