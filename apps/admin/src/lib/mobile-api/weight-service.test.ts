import { describe, expect, it } from 'vitest'
import { weightInputSchema } from './contracts'
import { loadProfile } from './read-model'
import {
  createSupabaseWeightDependencies,
  recordWeight,
  type WeightRecordInput,
  type WeightRecordResult,
} from './weight-service'

const measuredAt = '2026-09-28T08:30:00-03:00'

function repository(result?: Partial<WeightRecordResult>) {
  const calls: WeightRecordInput[] = []
  return {
    calls,
    deps: {
      repository: {
        async record(input: WeightRecordInput) {
          calls.push(input)
          return { ...answer(), ...result }
        },
      },
    },
  }
}

function answer(): WeightRecordResult {
  return {
    applied: true,
    reason: 'applied' as const,
    weight_kg: 78.46,
    measured_at: '2026-09-28T11:30:00+00:00',
  }
}

describe('mobile weight', () => {
  it('accepts kg and lb with an instant and nothing else', () => {
    expect(
      weightInputSchema.safeParse({ value: 78.4, unit: 'kg', measured_at: measuredAt }).success,
    ).toBe(true)
    expect(
      weightInputSchema.safeParse({ value: 170, unit: 'lb', measured_at: measuredAt }).success,
    ).toBe(true)
    for (const invalid of [
      { value: 78.4, unit: 'st', measured_at: measuredAt },
      { value: '78,4', unit: 'kg', measured_at: measuredAt },
      { value: 0, unit: 'kg', measured_at: measuredAt },
      { value: -70, unit: 'kg', measured_at: measuredAt },
      { value: 78.4, unit: 'kg' },
      { value: 78.4, unit: 'kg', measured_at: '2026-09-28 08:30' },
      { value: 78.4, unit: 'kg', measured_at: measuredAt, weight_kg: 60 },
      { value: 78.4, unit: 'kg', measured_at: measuredAt, user_id: 'someone-else' },
    ]) {
      expect(weightInputSchema.safeParse(invalid).success).toBe(false)
    }
  })

  it('sends the value and unit as received; the database converts and rounds', async () => {
    const { deps, calls } = repository()
    const result = await recordWeight(
      deps,
      'patient-1',
      { value: 170, unit: 'lb', measured_at: measuredAt },
      'key-12345678',
    )
    expect(calls).toEqual([
      {
        userId: 'patient-1',
        value: 170,
        unit: 'lb',
        measuredAt,
        idempotencyKey: 'key-12345678',
      },
    ])
    expect(result).toMatchObject({ applied: true, weight_kg: 78.46 })
  })

  it('reports a measurement that was not applied without turning it into an error', async () => {
    const { deps } = repository({ applied: false, reason: 'older_than_current', weight_kg: 77.9 })
    await expect(
      recordWeight(
        deps,
        'patient-1',
        { value: 90, unit: 'kg', measured_at: measuredAt },
        'key-12345678',
      ),
    ).resolves.toMatchObject({ applied: false, reason: 'older_than_current', weight_kg: 77.9 })
  })

  it.each([
    [{ value: 29.9, unit: 'kg' as const }, 'weight_out_of_range'],
    [{ value: 300.1, unit: 'kg' as const }, 'weight_out_of_range'],
    [{ value: 66, unit: 'lb' as const }, 'weight_out_of_range'],
    [{ value: 662, unit: 'lb' as const }, 'weight_out_of_range'],
  ])('refuses %j before reaching the database', async (value, code) => {
    const { deps, calls } = repository()
    await expect(
      recordWeight(deps, 'patient-1', { ...value, measured_at: measuredAt }, 'key-12345678'),
    ).rejects.toMatchObject({ status: 422, code })
    expect(calls).toEqual([])
  })

  it.each([
    '2026-09-28T12:06:00.000Z',
    '2026-09-21T11:59:00.000Z',
  ])('lets the authoritative database distinguish an aged replay from a new invalid instant (%s)', async (instant) => {
    const { deps, calls } = repository()
    await expect(
      recordWeight(
        deps,
        'patient-1',
        { value: 78, unit: 'kg', measured_at: instant },
        'key-12345678',
      ),
    ).resolves.toEqual(answer())
    expect(calls).toEqual([
      {
        userId: 'patient-1',
        value: 78,
        unit: 'kg',
        measuredAt: instant,
        idempotencyKey: 'key-12345678',
      },
    ])
  })

  it('maps database outcomes to typed errors and binds the call to the authenticated patient', async () => {
    const calls: Array<{ fn: string; params: Record<string, unknown> }> = []
    const client = (error: { code: string; message: string } | null, data: unknown) =>
      ({
        rpc: async (fn: string, params: Record<string, unknown>) => {
          calls.push({ fn, params })
          return { data, error }
        },
      }) as never
    const input = { value: 78, unit: 'kg' as const, measured_at: measuredAt }

    await expect(
      recordWeight(
        createSupabaseWeightDependencies(client({ code: '23505', message: 'x' }, null)),
        'patient-1',
        input,
        'key-12345678',
      ),
    ).rejects.toMatchObject({ status: 409, code: 'weight_measurement_conflict' })
    await expect(
      recordWeight(
        createSupabaseWeightDependencies(client({ code: '22023', message: 'x' }, null)),
        'patient-1',
        input,
        'key-12345678',
      ),
    ).rejects.toMatchObject({ status: 422, code: 'weight_out_of_range' })
    await expect(
      recordWeight(
        createSupabaseWeightDependencies(client({ code: 'XX000', message: 'secret detail' }, null)),
        'patient-1',
        input,
        'key-12345678',
      ),
    ).rejects.toMatchObject({
      status: 500,
      code: 'weight_storage_failed',
      message: 'Weight operation failed',
    })
    await expect(
      recordWeight(
        createSupabaseWeightDependencies(client(null, { applied: true })),
        'patient-1',
        input,
        'key-12345678',
      ),
    ).rejects.toMatchObject({ status: 500, code: 'weight_storage_failed' })

    expect(calls[0]).toEqual({
      fn: 'record_weight_atomic',
      params: {
        p_user_id: 'patient-1',
        p_value: 78,
        p_unit: 'kg',
        p_measured_at: measuredAt,
        p_idempotency_key: 'key-12345678',
      },
    })
  })

  it.each([
    ['40001', 'mobile_weight_request_conflict', 409, 'idempotency_key_conflict'],
    ['22023', 'mobile_weight_measured_at_out_of_range', 422, 'measured_at_out_of_range'],
    ['55P03', 'mobile_weight_busy', 409, 'weight_operation_busy'],
    ['40001', 'unrelated serialization failure', 500, 'weight_storage_failed'],
    ['55P03', 'unrelated busy detail', 500, 'weight_storage_failed'],
  ])('maps only named authoritative refusals (%s, %s)', async (code, message, status, publicCode) => {
    let calls = 0
    const deps = createSupabaseWeightDependencies({
      rpc: async () => {
        calls += 1
        return { data: null, error: { code, message } }
      },
    } as never)
    await expect(
      recordWeight(
        deps,
        'patient-1',
        { value: 78, unit: 'kg', measured_at: measuredAt },
        'key-12345678',
      ),
    ).rejects.toMatchObject({ status, code: publicCode })
    expect(calls).toBe(1)
  })
})

describe('profile read with the weight instant', () => {
  function supabase(hasColumn: boolean) {
    const selections: string[] = []
    return {
      selections,
      client: {
        from: () => ({
          select(columns: string) {
            selections.push(columns)
            return {
              eq: () => ({
                async maybeSingle() {
                  if (columns.includes('weight_measured_at') && !hasColumn) {
                    return {
                      data: null,
                      error: { code: '42703', message: 'column does not exist' },
                    }
                  }
                  return {
                    data: {
                      weight_kg: 78.46,
                      ...(columns.includes('weight_measured_at')
                        ? {
                            weight_measured_at: '2026-09-28T11:30:00+00:00',
                            weight_instant_source: 'recorded',
                          }
                        : {}),
                    },
                    error: null,
                  }
                },
              }),
            }
          },
        }),
      } as never,
    }
  }

  it('returns the instant and says what it is (a write is not a measurement)', async () => {
    const { client, selections } = supabase(true)
    await expect(loadProfile(client, 'patient-1')).resolves.toMatchObject({
      weight_kg: 78.46,
      weight_measured_at: '2026-09-28T11:30:00+00:00',
      weight_instant_source: 'recorded',
    })
    expect(selections[0]).toContain('weight_instant_source')
  })

  it('still answers on a database without the column, with the instant unknown', async () => {
    const { client, selections } = supabase(false)
    await expect(loadProfile(client, 'patient-1')).resolves.toEqual({
      weight_kg: 78.46,
      weight_measured_at: null,
      weight_instant_source: null,
    })
    expect(selections).toHaveLength(2)
  })
})
