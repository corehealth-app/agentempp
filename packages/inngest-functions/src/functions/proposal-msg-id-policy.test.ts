/**
 * Tests — classifyProposalMsgIdWrite (audit 06-26 review HIGH 2).
 */
import { describe, expect, it } from 'vitest'
import { classifyProposalMsgIdWrite } from './proposal-msg-id-policy.js'

describe('classifyProposalMsgIdWrite', () => {
  it('1º envio (rowWasSet=true) → pending.interactive_set', () => {
    const r = classifyProposalMsgIdWrite({
      rowWasSet: true,
      messageId: '10000000-0000-0000-0000-000000000001',
      newProviderMessageId: 'wamid-abc-123',
    })
    expect(r.event).toBe('pending.interactive_set')
    expect(r.properties).toEqual({
      providerMessageId: 'wamid-abc-123',
      messageId: '10000000-0000-0000-0000-000000000001',
      wasSet: true,
    })
  })

  it('re-envio (rowWasSet=false porque .is null falhou) → pending.interactive_resent', () => {
    const r = classifyProposalMsgIdWrite({
      rowWasSet: false,
      messageId: '10000000-0000-0000-0000-000000000002',
      newProviderMessageId: 'wamid-resend-456',
    })
    expect(r.event).toBe('pending.interactive_resent')
    expect(r.properties.wasSet).toBe(false)
    expect(r.properties.providerMessageId).toBe('wamid-resend-456')
  })

  it('eventos são mutuamente exclusivos por construção', () => {
    const set = classifyProposalMsgIdWrite({
      rowWasSet: true,
      messageId: '10000000-0000-0000-0000-000000000003',
      newProviderMessageId: 'x',
    })
    const resent = classifyProposalMsgIdWrite({
      rowWasSet: false,
      messageId: '10000000-0000-0000-0000-000000000004',
      newProviderMessageId: 'y',
    })
    expect(set.event).not.toBe(resent.event)
  })
})
