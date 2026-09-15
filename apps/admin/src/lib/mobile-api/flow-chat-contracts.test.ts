import { describe, expect, it } from 'vitest'
import { flowChatInputSchema, flowChatLimitSchema } from './contracts'

describe('Flow chat contracts', () => {
  it('trims a bounded text message', () => {
    expect(flowChatInputSchema.parse({ text: '  Olá, Flow  ' })).toEqual({ text: 'Olá, Flow' })
  })

  it('rejects empty, oversized, and caller-owned fields', () => {
    expect(flowChatInputSchema.safeParse({ text: '   ' }).success).toBe(false)
    expect(flowChatInputSchema.safeParse({ text: 'a'.repeat(4001) }).success).toBe(false)
    expect(flowChatInputSchema.safeParse({ text: 'oi', user_id: 'other' }).success).toBe(false)
    expect(flowChatInputSchema.safeParse({ text: 'oi', tool: 'registra_refeicao' }).success).toBe(
      false,
    )
  })

  it('bounds history pagination', () => {
    expect(flowChatLimitSchema.parse('20')).toBe(20)
    expect(flowChatLimitSchema.safeParse('0').success).toBe(false)
    expect(flowChatLimitSchema.safeParse('51').success).toBe(false)
  })
})
