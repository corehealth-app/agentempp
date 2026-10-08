import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { loadFlowPresentationContext } from './flow-presentation-context'
import type { MobileRouteContext } from './route'

function client(read: (owner: string) => Promise<{ data: unknown; error: unknown }>) {
  const calls: string[][] = []
  const supabase = {
    from(table: string) {
      calls.push(['from', table])
      return {
        select(columns: string) {
          calls.push(['select', columns])
          return {
            eq(key: string, owner: string) {
              calls.push(['eq', key, owner])
              return {
                maybeSingle() {
                  calls.push(['maybeSingle'])
                  return read(owner)
                },
              }
            },
          }
        },
      }
    },
  } as unknown as ServiceClient
  const context = (owner: string) =>
    ({ supabase, auth: { userId: owner, authUserId: `auth-${owner}` } }) as MobileRouteContext
  return { calls, context }
}

describe('Flow presentation context ownership and normalization', () => {
  it.each([
    ['recomposicao', 'recomposicao'],
    ['ganho_massa', 'ganho_massa'],
    ['manutencao', 'manutencao'],
    [null, null],
    [undefined, null],
    ['unknown', null],
    ['RECOMPOSICAO', null],
    [' recomposicao ', null],
    ['recomposição', null],
    ['recomposition', null],
    [7700, null],
    [false, null],
    [{ current_protocol: 'recomposicao' }, null],
  ])('reads only the domain owner and does not infer a protocol from %s', async (raw, expected) => {
    const row = Object.freeze({ current_protocol: raw })
    const { context, calls } = client(async (owner) => {
      expect(owner).toBe('patient-A')
      return { data: row, error: null }
    })
    expect(await loadFlowPresentationContext(context('patient-A'))).toEqual({
      currentProtocol: expected,
    })
    expect(calls).toEqual([
      ['from', 'user_profiles'],
      ['select', 'current_protocol'],
      ['eq', 'user_id', 'patient-A'],
      ['maybeSingle'],
    ])
    expect(row.current_protocol).toBe(raw)
  })

  it('keeps an absent profile unknown', async () => {
    const { context } = client(async () => ({ data: null, error: null }))
    expect(await loadFlowPresentationContext(context('patient-A'))).toEqual({
      currentProtocol: null,
    })
  })

  it.each([
    'error-result',
    'rejection',
  ])('fails safely on a %s instead of returning an absent objective', async (kind) => {
    const { context } = client(async () => {
      if (kind === 'rejection') throw new Error('synthetic query detail')
      return {
        data: { current_protocol: 'recomposicao' },
        error: { message: 'synthetic query detail' },
      }
    })
    await expect(loadFlowPresentationContext(context('patient-A'))).rejects.toMatchObject({
      status: 500,
      code: 'data_access_failed',
      message: 'Unable to read Flow presentation context',
    })
  })

  it('isolates concurrent A and B reads even when B finishes first, then rereads A', async () => {
    let resolveA: ((value: { data: unknown; error: null }) => void) | undefined
    const pendingA = new Promise<{ data: unknown; error: null }>((resolve) => {
      resolveA = resolve
    })
    let aRead = 0
    const { context, calls } = client(async (owner) => {
      if (owner === 'patient-B') return { data: { current_protocol: 'ganho_massa' }, error: null }
      expect(owner).toBe('patient-A')
      aRead += 1
      return aRead === 1 ? pendingA : { data: { current_protocol: 'manutencao' }, error: null }
    })
    const a = loadFlowPresentationContext(context('patient-A'))
    expect(await loadFlowPresentationContext(context('patient-B'))).toEqual({
      currentProtocol: 'ganho_massa',
    })
    resolveA?.({ data: { current_protocol: 'recomposicao' }, error: null })
    expect(await a).toEqual({ currentProtocol: 'recomposicao' })
    expect(await loadFlowPresentationContext(context('patient-A'))).toEqual({
      currentProtocol: 'manutencao',
    })
    expect(calls.filter((call) => call[0] === 'eq')).toEqual([
      ['eq', 'user_id', 'patient-A'],
      ['eq', 'user_id', 'patient-B'],
      ['eq', 'user_id', 'patient-A'],
    ])
  })
})
