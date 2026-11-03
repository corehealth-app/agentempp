import { describe, expect, it } from 'vitest'
import {
  bindConversationCommand,
  conversationMealCommandSchema,
} from './conversation-command-contracts'

const owner = '10000000-0000-4000-8000-000000000001'
const commandId = '10000000-0000-4000-8000-000000000002'
const assetId = '10000000-0000-4000-8000-000000000003'
const command = () => ({
  command_protocol: 'conversation.command.v1',
  command_id: commandId,
  kind: 'meal.report',
  meal_type: 'cafe',
  source: { channel: 'text', text: 'Comi arroz 200 g' },
})

describe('closed conversation command identity', () => {
  it('binds original validated content to authenticated owner and command UUID', () => {
    const input = command()
    const bound = bindConversationCommand(owner, `cmsg1:${commandId}`, input)
    expect(bound.ownerId).toBe(owner)
    expect(bound.commandId).toBe(commandId)
    expect(bound.command.meal_type).toBe('cafe')
    expect(bound.inputHash).toMatch(/^[a-f0-9]{64}$/)
    expect(Object.isFrozen(bound.command.source)).toBe(true)
    input.source.text = 'different'
    expect(bound.command.source).toEqual({ channel: 'text', text: 'Comi arroz 200 g' })
  })
  it('same content replays across property ordering; source changes conflict; new UUID is distinct', () => {
    const a = bindConversationCommand(owner, `cmsg1:${commandId}`, command())
    const b = bindConversationCommand(owner, `cmsg1:${commandId}`, {
      source: { text: 'Comi arroz 200 g', channel: 'text' },
      meal_type: 'cafe',
      kind: 'meal.report',
      command_id: commandId,
      command_protocol: 'conversation.command.v1',
    })
    expect(a.inputHash).toBe(b.inputHash)
    for (const change of [
      { ...command(), source: { channel: 'text', text: 'Comi arroz 201 g' } },
      { ...command(), meal_type: 'almoco' },
      { ...command(), source: { channel: 'text', text: ' Comi arroz 200 g ' } },
    ])
      expect(bindConversationCommand(owner, `cmsg1:${commandId}`, change).inputHash).not.toBe(
        a.inputHash,
      )
    const other = '10000000-0000-4000-8000-000000000004'
    expect(
      bindConversationCommand(owner, `cmsg1:${other}`, { ...command(), command_id: other }),
    ).toMatchObject({ commandId: other })
  })
  it('accepts an owned-asset reference, not public URLs or forged extraction', () => {
    const media = {
      ...command(),
      source: {
        channel: 'media',
        media_asset_id: assetId,
        user_action: 'register_consumed_meal',
        caption: 'Meu almoço',
      },
    }
    expect(conversationMealCommandSchema.parse(media)).toEqual(media)
    for (const field of ['url', 'transcript', 'processing_result', 'items', 'calories', 'owner_id'])
      expect(
        conversationMealCommandSchema.safeParse({
          ...media,
          source: { ...media.source, [field]: 'forged' },
        }).success,
      ).toBe(false)
    expect(
      conversationMealCommandSchema.safeParse({
        ...media,
        source: { ...media.source, user_action: 'chat_attachment' },
      }).success,
    ).toBe(false)
  })
  it.each([
    'user_id',
    'epoch',
    'snapshot',
    'clinical_policy',
    'calories',
    'feedback',
    'occurred_at',
  ])('rejects client authority field %s', (field) => {
    expect(
      conversationMealCommandSchema.safeParse({ ...command(), [field]: 'forged' }).success,
    ).toBe(false)
  })
  it('rejects blank, oversized or control input without silently trimming or truncating', () => {
    for (const text of ['', '  ', 'x'.repeat(2001), 'Comi\u0000arroz'])
      expect(
        conversationMealCommandSchema.safeParse({ ...command(), source: { channel: 'text', text } })
          .success,
      ).toBe(false)
    expect(
      conversationMealCommandSchema.parse({
        ...command(),
        source: {
          channel: 'text',
          text: '  Comi arroz 200 g  ',
        },
      }).source,
    ).toEqual({ channel: 'text', text: '  Comi arroz 200 g  ' })
  })
  it('requires the exact header and canonical UUID and never accepts unauthenticated owner', () => {
    for (const key of [null, '', 'another', `cmsg1:${assetId}`, `cmsg1:${commandId} `])
      expect(() => bindConversationCommand(owner, key, command())).toThrow()
    expect(() => bindConversationCommand('invalid', `cmsg1:${commandId}`, command())).toThrow()
    const uppercase = commandId.replace('1000', 'ABCD')
    expect(
      conversationMealCommandSchema.safeParse({ ...command(), command_id: uppercase }).success,
    ).toBe(false)
  })
})
