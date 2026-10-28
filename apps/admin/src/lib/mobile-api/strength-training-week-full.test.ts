import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { createCurrentClinicalGetRoute } from './current-clinical-http'
import type { createCurrentClinicalReadModel } from './current-clinical-read-model'
import {
  createStrengthWeekRepository,
  type StrengthWeekTarget,
} from './strength-training-week-service'

const id = (n: number) => `a7100000-0000-4000-8000-${String(n).padStart(12, '0')}`
const target = (): StrengthWeekTarget => ({
  target_id: id(4),
  user_id: id(1),
  generation: id(2),
  week_start: '2026-11-02',
  timezone_at_freeze: 'UTC',
  frozen_at: '2026-11-02T12:00:00.000001Z',
  source: 'informed_frequency',
  planned_days: 4,
  source_key: id(6),
  source_proof: {
    plan: { coverage: 'covered', source_version_id: id(5), source_order: '21' },
    frequency: { coverage: 'covered', source_version_id: id(6), source_order: '22' },
  },
})
function wire() {
  return {
    status: 'available',
    target: target(),
    binding: {
      kind: 'clinical_full',
      ownerID: id(1),
      generation: id(2),
      epoch: id(7),
      lifecycleKey: id(3),
      clinicalGeneration: id(8),
      reviewID: id(9),
      frequencySourceVersionID: id(10),
      workoutAdmissionID: id(11),
      workoutContentRevision: 0,
      boundAt: '2026-10-28T18:00:00.000001Z',
    },
    calendar: {
      ownerID: id(1),
      lifecycleKey: id(3),
      scopeKey: id(12),
      timeZone: 'UTC',
      weekStartDate: '2026-11-02',
      asOfLocalDate: '2026-11-04',
    },
    projection: { status: 'available', workouts: [] },
    observed_at: '2026-11-04T12:00:00.000001Z',
  }
}
function boundary(data: unknown, current = true, enabled = true) {
  const calls: string[] = []
  const client = {
    async rpc(name: string) {
      calls.push(name)
      return { data, error: null }
    },
  }
  const options = { enabled, clinicalFullAuthority: current }
  return {
    calls,
    repository: createStrengthWeekRepository(client as unknown as ServiceClient, options),
  }
}
describe('current clinical weekly projection authority', () => {
  it('selects v2 only for the explicit current clinical consumer', async () => {
    const b = boundary({ status: 'unavailable', reason: 'binding_unproved' })
    await expect(b.repository.projectAcquiredTarget(id(1), target())).resolves.toEqual({
      status: 'unavailable',
      reason: 'binding_unproved',
    })
    expect(b.calls).toEqual(['get_mobile_strength_week_projection_v2'])
  })
  it('preserves the existing RPC for the legacy consumer', async () => {
    const b = boundary({ status: 'unavailable', reason: 'binding_unproved' }, false)
    await b.repository.projectAcquiredTarget(id(1), target())
    expect(b.calls).toEqual(['get_mobile_strength_week_projection'])
  })
  it('keeps the disabled current consumer lazy', async () => {
    const b = boundary(wire(), true, false)
    await expect(b.repository.projectAcquiredTarget(id(1), target())).resolves.toEqual({
      status: 'disabled',
    })
    expect(b.calls).toEqual([])
  })
  it('accepts the independent FULL binding without inventing a signup ID', async () => {
    const b = boundary(wire())
    const result = await b.repository.projectAcquiredTarget(id(1), target())
    expect(result.status).toBe('available')
    expect(result).toHaveProperty('binding.kind', 'clinical_full')
    expect(result).not.toHaveProperty('binding.signupAdmissionID')
  })
  it.each([
    'kind',
    'clinicalGeneration',
    'reviewID',
  ])('refuses an incomplete FULL proof: %s', async (key) => {
    const raw = wire()
    Reflect.deleteProperty(raw.binding, key)
    const b = boundary(raw)
    await expect(b.repository.projectAcquiredTarget(id(1), target())).rejects.toMatchObject({
      code: 'strength_week_invalid_response',
    })
  })
  it('refuses mixing signup and FULL proof fields', async () => {
    const raw = wire()
    const b = boundary({ ...raw, binding: { ...raw.binding, signupAdmissionID: id(13) } })
    await expect(b.repository.projectAcquiredTarget(id(1), target())).rejects.toMatchObject({
      code: 'strength_week_invalid_response',
    })
  })
  it('accepts only the tagged signup proof on the current consumer', async () => {
    const raw = wire()
    const { clinicalGeneration: _generation, reviewID: _review, ...common } = raw.binding
    const tagged = {
      ...raw,
      binding: { ...common, kind: 'signup_receipt', signupAdmissionID: id(14) },
    }
    const b = boundary(tagged)
    await expect(b.repository.projectAcquiredTarget(id(1), target())).resolves.toHaveProperty(
      'binding.kind',
      'signup_receipt',
    )
    const { kind: _kind, ...untagged } = tagged.binding
    await expect(
      boundary({ ...raw, binding: untagged }).repository.projectAcquiredTarget(id(1), target()),
    ).rejects.toMatchObject({ code: 'strength_week_invalid_response' })
  })
  it('keeps FULL proof unavailable to the legacy parser', async () => {
    await expect(
      boundary(wire(), false).repository.projectAcquiredTarget(id(1), target()),
    ).rejects.toMatchObject({ code: 'strength_week_invalid_response' })
  })
  it('uses v2 through the actual current Today HTTP constructor and hides internal proof', async () => {
    const calls: string[] = []
    const client = {
      async rpc(name: string) {
        calls.push(name)
        if (name === 'get_mobile_strength_week_context')
          return {
            data: {
              status: 'ready',
              context: {
                kind: 'existing_target',
                user_id: id(1),
                generation: id(2),
                timezone: 'UTC',
                week_start: '2026-11-02',
                observed_at: '2026-11-04T12:00:00.000001Z',
                target: target(),
              },
            },
            error: null,
          }
        if (name === 'freeze_mobile_strength_week_target')
          return { data: { status: 'reused', target: target() }, error: null }
        if (name === 'get_mobile_strength_week_projection_v2') return { data: wire(), error: null }
        throw new Error('Unexpected weekly RPC')
      },
    } as unknown as ServiceClient
    const model = {
      async preflight() {
        calls.push('preflight')
        return { owner: id(1) }
      },
      async today(
        _auth: unknown,
        _url: string,
        decorate?: (owner: string, data: unknown) => Promise<unknown>,
      ) {
        calls.push('today')
        const data = { current_protocol: 'recomposicao', marker: 'daily stays' }
        return decorate ? decorate(id(1), data) : data
      },
    } as unknown as ReturnType<typeof createCurrentClinicalReadModel>
    const auth = {
      accessToken: 'synthetic',
      authUserId: id(40),
      userId: id(1),
      identity: { id: id(40), email: null, emailConfirmedAt: null },
      patient: {
        id: id(1),
        authUserId: id(40),
        email: null,
        name: null,
        locale: 'pt-BR',
        timezone: 'UTC',
        country: 'BR',
        countryConfirmed: true,
        status: 'active' as const,
      },
    }
    const handler = createCurrentClinicalGetRoute(
      'today',
      {
        createServiceClient: () => client,
        createRequestId: () => 'qa-week-current',
        authenticate: async () => {
          calls.push('auth')
          return auth
        },
        authorizeEntitlement: async () => {
          calls.push('entitlement')
        },
      },
      {
        createReadModel: () => model,
        applyDaily: async () => {
          calls.push('daily')
        },
        closeDays: async () => {
          calls.push('closer')
        },
      },
      () => true,
    )
    const response = await handler(new Request('https://bodyflow.test/api/mobile/v1/today'))
    expect(response.status).toBe(200)
    const body = await response.json()
    expect(body.data.marker).toBe('daily stays')
    expect(body.data.strength_training_week).toEqual({
      status: 'available',
      week_start: '2026-11-02',
      as_of_local_date: '2026-11-04',
      time_zone: 'UTC',
      observed_at: '2026-11-04T12:00:00.000001Z',
      completed_strength_days: 0,
      planned_days: 4,
      target_source: 'informed_frequency',
      target_availability: 'available',
      percentage: 0,
    })
    expect(calls).toEqual([
      'auth',
      'entitlement',
      'preflight',
      'daily',
      'closer',
      'today',
      'get_mobile_strength_week_context',
      'freeze_mobile_strength_week_target',
      'get_mobile_strength_week_projection_v2',
    ])
    expect(JSON.stringify(body)).not.toContain('clinicalGeneration')
    expect(JSON.stringify(body)).not.toContain('reviewID')
    expect(JSON.stringify(body)).not.toContain('clinical_full')
  })
})
