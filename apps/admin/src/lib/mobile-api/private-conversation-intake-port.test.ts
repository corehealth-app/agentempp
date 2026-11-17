import { describe, expect, it } from 'vitest'
import actual from './__fixtures__/conversation-private-media-actual.json'
import { bindConversationIntake } from './conversation-intake-contracts'
import { createConversationIntakeStore } from './conversation-intake-store'
import { createPrivateConversationIntakePort } from './private-conversation-intake-port'

const row = actual.rows[0]
if (!row) throw new Error('Actual private capture fixture required')
const parent = bindConversationIntake(
  row.neutral.context.owner_id,
  `cintake1:${row.neutral.context.intake_id}`,
  row.neutral.context.source_input,
)
const epoch = row.selection.intake.epoch

describe('explicit private admission port with the existing scoped store', () => {
  it('selects the private admission RPC without changing the input hash or source DTO', async () => {
    const calls: { name: string; args: Readonly<Record<string, unknown>> }[] = []
    const port = createPrivateConversationIntakePort({
      rpc: async (name, args) => {
        calls.push({ name, args })
        return { error: null, data: { action: 'admitted', intake: row.selection.intake } }
      },
    })
    const store = createConversationIntakeStore(port, { checkCurrentScope: async () => true })
    expect(await store.admit(parent, epoch)).toEqual({
      action: 'admitted',
      intake: row.selection.intake,
    })
    expect(calls).toEqual([
      {
        name: 'admit_conversation_private_media_intake_v2',
        args: { p_user_id: parent.ownerId, p_expected_epoch: epoch, p_input: parent.input },
      },
    ])
  })

  it('keeps text admissions on the original RPC', async () => {
    const text = bindConversationIntake(parent.ownerId, `cintake1:${parent.intakeId}`, {
      ...parent.input,
      source: { channel: 'text', text: 'Comi arroz 100 g' },
    })
    const calls: string[] = []
    const store = createConversationIntakeStore(
      createPrivateConversationIntakePort({
        rpc: async (name) => {
          calls.push(name)
          return {
            error: null,
            data: {
              action: 'admitted',
              intake: { ...row.selection.intake, input_hash: text.inputHash },
            },
          }
        },
      }),
      { checkCurrentScope: async () => true },
    )
    expect((await store.admit(text, epoch)).action).toBe('admitted')
    expect(calls).toEqual(['admit_conversation_intake'])
  })

  it('preserves the existing Auth/owner observer before any physical call', async () => {
    const calls: string[] = []
    const store = createConversationIntakeStore(
      createPrivateConversationIntakePort({
        rpc: async (name) => {
          calls.push(name)
          throw new Error('must not run')
        },
      }),
      { checkCurrentScope: async () => false },
    )
    await expect(store.admit(parent, epoch)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(calls).toEqual([])
  })

  it('does not fall back to legacy admission after an uncertain private response', async () => {
    const calls: string[] = []
    const store = createConversationIntakeStore(
      createPrivateConversationIntakePort({
        rpc: async (name) => {
          calls.push(name)
          throw new Error('private provider diagnostic')
        },
      }),
      { checkCurrentScope: async () => true },
    )
    await expect(store.admit(parent, epoch)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(calls).toEqual(['admit_conversation_private_media_intake_v2'])
  })

  it('preserves a private media refusal rather than admitting a different source', async () => {
    const calls: string[] = []
    const store = createConversationIntakeStore(
      createPrivateConversationIntakePort({
        rpc: async (name) => {
          calls.push(name)
          return { error: null, data: { action: 'input_conflict' } }
        },
      }),
      { checkCurrentScope: async () => true },
    )
    expect(await store.admit(parent, epoch)).toEqual({ action: 'input_conflict' })
    expect(calls).toEqual(['admit_conversation_private_media_intake_v2'])
  })
})
