import { describe, expect, it } from 'vitest'
import { hashMobileRequest } from './idempotency'
import { classifySignupCompletionTransport } from './signup-completion-transport'

const ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const KEY = `osc1:${ID}`
const clinical = () => ({ name: 'Synthetic QA', document_actions: [{ version: 'fixture' }] })
const versioned = () => ({
  ...clinical(),
  signup_strength_protocol: 'osc1',
  completion_intent_id: ID,
})

describe('signup completion transport provenance', () => {
  it.each([
    ID,
    'signup-original-key',
    'old.key:part_1',
    'oscillator-old-key',
    null,
  ])('leaves unmarked legacy requests unchanged (%s)', (key) => {
    const body = clinical()
    const result = classifySignupCompletionTransport(body, key)
    expect(result).toEqual({ mode: 'legacy', body })
    expect(result.body).toBe(body)
  })

  it.each([
    null,
    [],
    'invalid',
    5,
    { name: 'partial draft' },
  ])('leaves unmarked body validation to the existing legacy handler (%j)', (body) => {
    expect(classifySignupCompletionTransport(body, 'legacy-key-1')).toEqual({
      mode: 'legacy',
      body,
    })
  })

  it('extracts the issued tuple and excludes transport metadata from the clinical hash', () => {
    const body = versioned()
    const result = classifySignupCompletionTransport(body, KEY)
    expect(result).toEqual({ mode: 'versioned', intentId: ID, requestKey: KEY, body: clinical() })
    expect(hashMobileRequest(result.body)).toBe(hashMobileRequest(clinical()))
    expect(body).toEqual(versioned())
  })

  it.each([
    ['reserved key without metadata', clinical(), KEY],
    ['protocol without receipt', { ...clinical(), signup_strength_protocol: 'osc1' }, KEY],
    ['receipt without protocol', { ...clinical(), completion_intent_id: ID }, KEY],
    ['marker with legacy key', versioned(), 'signup-original-key'],
    ['marker with absent key', versioned(), null],
    ['unknown protocol', { ...versioned(), signup_strength_protocol: 'osc2' }, KEY],
    ['null protocol', { ...versioned(), signup_strength_protocol: null }, KEY],
    ['undefined own protocol', { ...versioned(), signup_strength_protocol: undefined }, KEY],
    ['array protocol', { ...versioned(), signup_strength_protocol: ['osc1'] }, KEY],
    ['invalid receipt', { ...versioned(), completion_intent_id: 'invalid' }, KEY],
    ['null receipt', { ...versioned(), completion_intent_id: null }, KEY],
    ['incomplete namespace', clinical(), 'osc1'],
    ['empty namespace', clinical(), 'osc:legacy-key'],
    ['unknown namespace', clinical(), `osc2:${ID}`],
    ['NBSP-prefixed reserved key normalized by the legacy key schema', clinical(), `\u00a0${KEY}`],
    ['padded reserved key normalized by the legacy key schema', clinical(), ` ${KEY} `],
    ['NBSP-suffixed reserved key normalized by the legacy key schema', clinical(), `${KEY}\u00a0`],
    ['noncanonical key', versioned(), `OSC1:${ID}`],
    ['malformed reserved key', versioned(), 'osc1:not-a-uuid'],
    ['reserved key with suffix', versioned(), `${KEY}:extra`],
    [
      'versioned partial update',
      {
        name: 'partial draft',
        signup_strength_protocol: 'osc1',
        completion_intent_id: ID,
      },
      KEY,
    ],
    ['versioned primitive', null, KEY],
    ['versioned array', [], KEY],
  ])('refuses %s before a caller can choose the legacy writer', (_label, body, key) => {
    expect(() => classifySignupCompletionTransport(body, key as string | null)).toThrowError(
      expect.objectContaining({ status: 400, code: 'invalid_signup_completion_transport' }),
    )
  })

  it('never changes the classification of a legacy retry as availability changes', () => {
    const body = clinical()
    const key = 'old-unadmitted-OFF-key'
    const before = classifySignupCompletionTransport(body, key)
    // Availability and the current epoch are deliberately not classifier inputs.
    const afterResetAndOn = classifySignupCompletionTransport(body, key)
    expect(before).toEqual({ mode: 'legacy', body })
    expect(afterResetAndOn).toEqual(before)
  })
})
