import { describe, expect, it } from 'vitest'
import { createTrainingExecutionStore } from './training-execution-store'

const owner = '13500000-0000-4000-8000-000000000002'
const auth = '13500000-0000-4000-8000-000000000001'
const session = '13500000-0000-4000-8000-000000000003'
const epoch = '13500000-0000-4000-8000-000000000004'
const command = {
  schema: 'training.execution.start.v1',
  session_id: session,
  operation_id: session,
  expected_epoch: epoch,
  expected_local_date: '2026-11-14',
  plan_id: '13500000-0000-4000-8000-000000000005',
  plan_hash: 'a'.repeat(64),
  day_index: 0,
}

describe('original-Auth training execution persistence boundary', () => {
  it('rejects client ownership/energy fields before invoking the database', async () => {
    let calls = 0
    const store = createTrainingExecutionStore(
      {
        rpc: async () => {
          calls++
          throw Error('must not call')
        },
      },
      { owner, auth },
    )
    await expect(
      store.mutate({ ...command, owner_id: owner, calories: 100 }),
    ).rejects.toMatchObject({ code: 'training_execution_invalid_command' })
    expect(calls).toBe(0)
  })
  it('binds capture to original Auth and owner, without leaking provider errors or retrying', async () => {
    const calls: unknown[] = []
    const store = createTrainingExecutionStore(
      {
        rpc: async (name, args) => {
          calls.push({ name, args })
          return { data: null, error: { message: 'private provider diagnostic', code: 'XX000' } }
        },
      },
      { owner, auth },
    )
    await expect(store.mutate(command)).rejects.toMatchObject({
      code: 'training_execution_store_unavailable',
    })
    expect(calls).toEqual([
      {
        name: 'capture_training_execution_context',
        args: {
          p_user_id: owner,
          p_auth_user_id: auth,
          p_session_id: session,
          p_operation_id: session,
        },
      },
    ])
  })
  it('rejects an oversized capture before interpreting a plan or attempting a commit', async () => {
    let calls = 0
    const store = createTrainingExecutionStore(
      {
        rpc: async () => {
          calls++
          return { data: { extra: 'a'.repeat(1048577) }, error: null }
        },
      },
      { owner, auth },
    )
    await expect(store.mutate(command)).rejects.toMatchObject({
      code: 'training_execution_store_unavailable',
    })
    expect(calls).toBe(1)
  })
})
