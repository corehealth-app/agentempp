import { beforeEach, describe, expect, it, vi } from 'vitest'
import { loadWorkoutAwarePendingRegistrations } from './workout-registration-service'

const state = vi.hoisted(() => ({ enabled: true }))
vi.mock('./workout-registration-switch', () => ({
  workoutRegistrationEnabled: () => state.enabled,
}))
const OWNER = '00000000-0000-4000-8000-000000000001'
const ID = '00000000-0000-4000-8000-000000000002'
const LEGACY = '00000000-0000-4000-8000-000000000003'
const rawProposal = {
  kind: 'workout',
  workoutType: 'Natação',
  durationMin: 40,
  kcalEst: 400,
  intensity: 'moderada',
  source_provider_message_id: 'private-key',
  raw_args: { private: true },
}
const row = {
  id: ID,
  proposal: rawProposal,
  status: 'pending',
  created_at: '2026-10-15T10:00:00Z',
  expires_at: '2099-10-16T10:00:00Z',
  resolved_at: null,
  workout_ui_admission_id: OWNER,
}
const projection = {
  ...row,
  workout_ui_admission_id: undefined,
  workout_protocol: 'ui-v1',
  content_revision: 2,
}

function database(reply: unknown) {
  const { workout_ui_admission_id: _marker, ...registration } = projection
  const data = reply === undefined ? { status: 'available', registration } : reply
  const rows = { data: [{ ...row, id: LEGACY, workout_ui_admission_id: null }, row], error: null }
  const query = {
    select: vi.fn(() => query),
    eq: vi.fn(() => query),
    gt: vi.fn(() => query),
    order: vi.fn(() => query),
    limit: vi.fn(() => Promise.resolve(rows)),
  }
  const rpc = vi.fn(async () => ({ data, error: null }))
  const from = vi.fn(() => query)
  return { client: { from, rpc } as never, from, rpc, query }
}

beforeEach(() => {
  state.enabled = true
})

describe('workout-aware pending list', () => {
  it('uses the current official version for protected rows and keeps legacy rows unchanged', async () => {
    const h = database(undefined)
    const result = await loadWorkoutAwarePendingRegistrations(h.client, OWNER)
    expect(result).toHaveLength(2)
    expect(result[0]).not.toHaveProperty('workout_protocol')
    expect(result[1]).toMatchObject({
      id: ID,
      workout_protocol: 'ui-v1',
      content_revision: 2,
      proposal: { workout_type: 'Natação' },
    })
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith('get_mobile_workout_registration', {
      p_user_id: OWNER,
      p_registration_id: ID,
    })
    expect(h.query.eq).toHaveBeenCalledWith('user_id', OWNER)
    expect(JSON.stringify(result)).not.toContain('private-key')
    expect(JSON.stringify(result)).not.toContain('workout_ui_admission_id')
    expect(JSON.stringify(result)).not.toContain('raw_args')
  })

  it('does not fall back to a legacy DTO when the protected projection is forbidden', async () => {
    const h = database({ status: 'forbidden', reason: 'invalid_admission' })
    await expect(loadWorkoutAwarePendingRegistrations(h.client, OWNER)).resolves.toMatchObject([
      { id: LEGACY },
    ])
  })

  it('does not display a proposal that became terminal after the list read', async () => {
    const { workout_ui_admission_id: _marker, ...registration } = projection
    const h = database({
      status: 'available',
      registration: { ...registration, status: 'cancelled', resolved_at: '2026-10-15T11:00:00Z' },
    })
    await expect(loadWorkoutAwarePendingRegistrations(h.client, OWNER)).resolves.toMatchObject([
      { id: LEGACY },
    ])
  })

  it('is inert while disabled, including queries and adapter construction', async () => {
    state.enabled = false
    const h = database(undefined)
    await expect(loadWorkoutAwarePendingRegistrations(h.client, OWNER)).rejects.toMatchObject({
      status: 503,
      code: 'workout_registration_unavailable',
    })
    expect(h.from).not.toHaveBeenCalled()
    expect(h.rpc).not.toHaveBeenCalled()
  })
})
