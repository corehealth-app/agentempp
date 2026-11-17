import { describe, expect, it } from 'vitest'
import actual from './__fixtures__/conversation-private-media-actual.json'
import { bindConversationIntake } from './conversation-intake-contracts'
import { createConversationIntakeStore } from './conversation-intake-store'
import { createVersionedConversationIntakePort } from './versioned-conversation-intake-port'

const row = actual.rows[0]
if (!row) throw Error('Actual private capture fixture required')
const parent = bindConversationIntake(
  row.neutral.context.owner_id,
  `cintake1:${row.neutral.context.intake_id}`,
  row.neutral.context.source_input,
)
const epoch = row.selection.intake.epoch
function setup(enabled = true) {
  const calls: Array<{ name: string; args: Readonly<Record<string, unknown>> }> = []
  let current = enabled
  const port = createVersionedConversationIntakePort(
    {
      rpc: async (name, args) => {
        calls.push({ name, args })
        return { data: { action: 'admitted', intake: row.selection.intake }, error: null }
      },
    },
    { enabled: () => current },
  )
  let observations = 0
  const store = createConversationIntakeStore(port, {
    checkCurrentScope: async () => {
      observations++
      return true
    },
  })
  return {
    calls,
    store,
    port,
    withdraw: () => {
      current = false
    },
    observations: () => observations,
  }
}
describe('atomic versioned intake port', () => {
  it('dispatches media admission atomically and retains the original hash and two real store observation boundaries', async () => {
    const x = setup()
    expect((await x.store.admit(parent, epoch)).action).toBe('admitted')
    expect(x.calls).toEqual([
      {
        name: 'admit_conversation_versioned_media_intake_v2',
        args: { p_user_id: parent.ownerId, p_expected_epoch: epoch, p_input: parent.input },
      },
    ])
    expect(x.observations()).toBe(2)
  })
  it('keeps media admission on the old transport when the request was bound with the opt-in off', async () => {
    const x = setup(false)
    await x.store.admit(parent, epoch)
    expect(x.calls.map((c) => c.name)).toEqual(['admit_conversation_intake'])
  })
  it('keeps text admission unchanged even when the private opt-in is on', async () => {
    const text = bindConversationIntake(parent.ownerId, `cintake1:${parent.intakeId}`, {
      ...parent.input,
      source: { channel: 'text', text: 'Comi arroz 100 g' },
    })
    const calls: string[] = []
    const port = createVersionedConversationIntakePort(
      {
        rpc: async (name) => {
          calls.push(name)
          return {
            data: {
              action: 'admitted',
              intake: { ...row.selection.intake, input_hash: text.inputHash },
            },
            error: null,
          }
        },
      },
      { enabled: () => true },
    )
    expect(
      (
        await createConversationIntakeStore(port, { checkCurrentScope: async () => true }).admit(
          text,
          epoch,
        )
      ).action,
    ).toBe('admitted')
    expect(calls).toEqual(['admit_conversation_intake'])
  })
  it('refuses owner/epoch observer withdrawal before the physical dispatcher', async () => {
    const x = setup()
    const store = createConversationIntakeStore(x.port, { checkCurrentScope: async () => false })
    await expect(store.admit(parent, epoch)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(x.calls).toEqual([])
  })
  it('refuses a withdrawn bound policy without falling back to public admission', async () => {
    const x = setup()
    x.withdraw()
    await expect(x.store.admit(parent, epoch)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(x.calls).toEqual([])
  })
  it('never retries through the legacy RPC after an uncertain dispatcher commit', async () => {
    const calls: string[] = []
    const port = createVersionedConversationIntakePort(
      {
        rpc: async (name) => {
          calls.push(name)
          throw Error('uncertain SQL commit')
        },
      },
      { enabled: () => true },
    )
    await expect(
      createConversationIntakeStore(port, { checkCurrentScope: async () => true }).admit(
        parent,
        epoch,
      ),
    ).rejects.toMatchObject({ code: 'conversation_intake_unavailable' })
    expect(calls).toEqual(['admit_conversation_versioned_media_intake_v2'])
  })
  it('refuses policy withdrawal during the physical call, without changing a later retry to legacy', async () => {
    let enabled = true
    const calls: string[] = []
    const port = createVersionedConversationIntakePort(
      {
        rpc: async (name) => {
          calls.push(name)
          enabled = false
          return { data: { action: 'admitted', intake: row.selection.intake }, error: null }
        },
      },
      { enabled: () => enabled },
    )
    const store = createConversationIntakeStore(port, { checkCurrentScope: async () => true })
    await expect(store.admit(parent, epoch)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    enabled = true
    await expect(store.admit(parent, epoch)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(calls).toHaveLength(1)
  })
})

it('preserves an explicit unavailable private source as a temporary admission refusal', async () => {
  const port = createVersionedConversationIntakePort(
    { rpc: async () => ({ data: { action: 'media_unavailable' }, error: null }) },
    { enabled: () => true },
  )
  const store = createConversationIntakeStore(port, { checkCurrentScope: async () => true })
  expect(await store.admit(parent, epoch)).toEqual({ action: 'media_unavailable' })
})
