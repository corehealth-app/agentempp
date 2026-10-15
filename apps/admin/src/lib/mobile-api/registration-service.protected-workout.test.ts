import { describe, expect, it, vi } from 'vitest'
import { cancelRegistration, confirmRegistration, editRegistration } from './registration-service'

const USER = '00000000-0000-4000-8000-000000000001'
const ID = '00000000-0000-4000-8000-000000000002'
const auth = { userId: USER, patient: { country: 'BR', timezone: 'America/Sao_Paulo' } } as never
const raw = {
  kind: 'workout',
  workoutType: 'Natação',
  durationMin: 40,
  kcalEst: 400,
  intensity: 'moderada',
  source_provider_message_id: 'internal-only',
}

function database(status: string, marker: string | null | undefined) {
  const row = {
    id: ID,
    user_id: USER,
    status,
    proposal: raw,
    created_at: '2026-10-15T10:00:00Z',
    expires_at: '2099-10-16T10:00:00Z',
    resolved_at: null,
    ...(marker === undefined ? {} : { workout_ui_admission_id: marker }),
  }
  const select = vi.fn((columns: string) => {
    // A pre-migration server cannot select a new column by name.
    if (marker === undefined && columns.includes('workout_ui_admission_id'))
      throw new Error('column does not exist')
    return query
  })
  const query = {
    select,
    eq: vi.fn(() => query),
    maybeSingle: vi.fn(async () => ({ data: row, error: null })),
  }
  const from = vi.fn((table: string) => {
    if (table !== 'pending_registrations')
      throw new Error('must not call a legacy workout writer/lookup')
    return query
  })
  return { client: { from } as never, from, query }
}

describe('legacy registration callers cannot mutate a protected workout by omitting its protocol', () => {
  it.each([
    'pending',
    'confirmed',
    'cancelled',
  ])('refuses protected %s before any legacy status handling/writer', async (status) => {
    const h = database(status, '00000000-0000-4000-8000-000000000003')
    for (const operation of [
      () => confirmRegistration(h.client, auth, ID),
      () => cancelRegistration(h.client, USER, ID),
      () =>
        editRegistration(
          h.client,
          auth,
          ID,
          { kind: 'workout', workout_type: 'Natação', duration_min: 45, intensity: 'moderada' },
          'legacy-key-1234',
        ),
    ]) {
      await expect(operation()).rejects.toMatchObject({
        status: 409,
        code: 'registration_revision_required',
      })
    }
    expect(h.from.mock.calls.every(([table]) => table === 'pending_registrations')).toBe(true)
  })

  it.each([
    undefined,
    null,
  ])('keeps a pre-migration/unprotected confirmed workout on its existing read-only response %#', async (marker) => {
    const h = database('confirmed', marker)
    await expect(confirmRegistration(h.client, auth, ID)).resolves.toMatchObject({
      id: ID,
      status: 'confirmed',
      already_confirmed: true,
      proposal: { kind: 'workout', workout_type: 'Natação', duration_min: 40, estimated_kcal: 400 },
    })
    expect(h.from).toHaveBeenCalledTimes(1)
  })
})
