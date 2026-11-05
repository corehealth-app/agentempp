import { describe, expect, it } from 'vitest'
import {
  bindConversationIntake,
  parseConversationIntakeBinding,
  parseConversationIntakeRoutingDecision,
  parseConversationIntakeSelection,
  parseConversationIntakeSource,
  pinConversationIntake,
} from './conversation-intake-contracts'

const owner = '0a1a0000-0000-4000-8000-000000000001'
const id = '0a1a0000-0000-4000-8000-000000000002'
const child = '0a1a0000-0000-4000-8000-000000000003'
const epoch = '0a1a0000-0000-4000-8000-000000000004'
const inputHash = 'ca56a1db694111ad33d6810121f148ceb4ee0b0853046eb882d67d8f7fcd6072'
const sourceHash = 'a'.repeat(64)
// Hand-specified JSON and independently SHA256'd canonical string; no hash helper under test.
function input() {
  return {
    intake_protocol: 'conversation.intake.v1',
    intake_id: id,
    source: { channel: 'text', text: '  fiz 30 min de caminhada  ' },
  }
}
function bound() {
  return bindConversationIntake(owner, `cintake1:${id}`, input())
}
function binding() {
  return {
    owner_id: owner,
    intake_id: id,
    input_hash: inputHash,
    epoch,
    admitted_at: '2026-11-05T12:00:00.000001Z',
  }
}
function source() {
  return {
    source_hash: sourceHash,
    context: {
      schema: 'conversation.intake-source.v1',
      ...binding(),
      source_input: input(),
      captured_at: '2026-11-05T12:00:01.000001Z',
      time_zone: 'America/Sao_Paulo',
      local_date: '2026-11-05',
      media: null,
    },
  }
}
function selection() {
  return {
    schema: 'conversation.intake-selection.v1',
    intake: binding(),
    source_hash: sourceHash,
    decision_hash: '45fa270e311da3872895adcb18bac775e743741b90fedd9ab54028a7dfc77b94',
    decision: {
      schema: 'conversation.intake-routing.v1',
      kind: 'workout.report',
      reason: 'performed_activity',
    },
    selected_at: '2026-11-05T12:00:03.000001Z',
    command: {
      kind: 'workout.report',
      owner_id: owner,
      command_id: child,
      input_hash: 'e96cf5b1d27f79355e6be9499c3c190cfce7767e3224aab24f824ab224dfd760',
      epoch,
      admitted_at: '2026-11-05T12:00:02.000001Z',
      input: {
        command_protocol: 'conversation.command.v1',
        command_id: child,
        kind: 'workout.report',
        source: input().source,
      },
    },
  }
}

describe('Immutable neutral intake contracts; parsing grants no Auth', () => {
  it('preserves literal text and independent neutral identity for two legitimate equal reports', () => {
    const raw = input(),
      b = bindConversationIntake(owner, `cintake1:${id}`, raw)
    expect(b).toEqual({ ownerId: owner, intakeId: id, inputHash, input: raw })
    raw.source.text = 'changed outside the boundary'
    expect(b.input.source).toEqual({ channel: 'text', text: '  fiz 30 min de caminhada  ' })
    expect(Object.isFrozen(b.input.source)).toBe(true)
    const second = { ...input(), intake_id: '0a1a0000-0000-4000-8000-000000000006' }
    expect(bindConversationIntake(owner, `cintake1:${second.intake_id}`, second).inputHash).toBe(
      '0b35ab95a442930790fa8cfe3c5761b2b21706c53b0f71e66d2d1b37847ebf06',
    )
    expect(pinConversationIntake(b)).toEqual(b)
    expect(() => pinConversationIntake({ ...b, inputHash: 'b'.repeat(64) })).toThrow()
  })
  it.each([
    'extra',
    'schema',
    'id',
    'kind',
    'blank',
    'control',
    'long',
    'wrongkey',
    'foreignowner',
    'mediaaction',
    'mediaprivate',
  ])('refuses invalid intake %s before identity publication', (attack) => {
    const raw: Record<string, unknown> = input()
    let key = `cintake1:${id}`,
      own = owner
    if (attack === 'extra') raw.private_state = true
    if (attack === 'schema') raw.intake_protocol = 'conversation.command.v1'
    if (attack === 'id') raw.intake_id = id.toUpperCase()
    if (attack === 'kind') raw.kind = 'meal.report'
    if (attack === 'blank') raw.source = { channel: 'text', text: '  ' }
    if (attack === 'control') raw.source = { channel: 'text', text: 'a\u0000b' }
    if (attack === 'long') raw.source = { channel: 'text', text: 'a'.repeat(2001) }
    if (attack === 'wrongkey') key = `cmsg1:${id}`
    if (attack === 'foreignowner') own = 'untrusted'
    if (attack === 'mediaaction')
      raw.source = {
        channel: 'media',
        media_asset_id: child,
        user_action: 'register_consumed_meal',
      }
    if (attack === 'mediaprivate')
      raw.source = {
        channel: 'media',
        media_asset_id: child,
        user_action: 'report_actual_record',
        processing_result: {},
      }
    expect(() => bindConversationIntake(own, key, raw)).toThrow()
  })
  it('validates actual captured context without fabricating a typed domain capture', () => {
    const raw = source()
    const value = parseConversationIntakeSource(bound(), binding(), raw)
    raw.context.source_input.source.text = 'mutated'
    expect(value.sourceHash).toBe(sourceHash)
    expect(value.context.source_input.source).toEqual({
      channel: 'text',
      text: '  fiz 30 min de caminhada  ',
    })
    expect(Object.isFrozen(value.context.source_input)).toBe(true)
    expect(value.binding).toEqual(binding())
    expect(parseConversationIntakeBinding(bound(), binding())).toEqual(binding())
  })
  it.each([
    'owner',
    'input',
    'epoch',
    'admit',
    'before',
    'nanosecond',
    'zone',
    'date',
    'midnight',
    'textmedia',
    'private',
    'hash',
  ])('rejects contradictory captured %s', (attack) => {
    const raw = source()
    const c: Record<string, unknown> = raw.context
    if (attack === 'owner') c.owner_id = child
    if (attack === 'input')
      c.source_input = { ...input(), source: { channel: 'text', text: 'different' } }
    if (attack === 'epoch') c.epoch = child
    if (attack === 'admit') c.admitted_at = '2026-11-05T11:59:59Z'
    if (attack === 'before') c.captured_at = '2026-11-05T11:59:59Z'
    if (attack === 'nanosecond') c.captured_at = '2026-11-05T12:00:00.000000999Z'
    if (attack === 'zone') c.time_zone = 'invalid/timezone'
    if (attack === 'date') c.local_date = '2026-11-06'
    if (attack === 'midnight') c.captured_at = '2026-11-06T03:00:00Z'
    if (attack === 'textmedia') c.media = {}
    if (attack === 'private') c.clinical = {}
    if (attack === 'hash') raw.source_hash = 'wrong'
    expect(() => parseConversationIntakeSource(bound(), binding(), raw)).toThrow()
  })
  it('accepts the genuine typed text binding and keeps the three independent hashes', () => {
    const raw = selection(),
      value = parseConversationIntakeSelection(bound(), binding(), raw)
    expect(value).toEqual(raw)
    expect(value.command?.input_hash).toBe(
      'e96cf5b1d27f79355e6be9499c3c190cfce7767e3224aab24f824ab224dfd760',
    )
    expect(value.intake.input_hash).toBe(inputHash)
    expect(value.source_hash).toBe(sourceHash)
    expect(Object.isFrozen(value.command?.input)).toBe(true)
  })
  it.each([
    'owner',
    'child',
    'hash',
    'epoch',
    'text',
    'kind',
    'before',
    'after',
    'extra',
    'decisionhash',
    'question',
    'missingcommand',
  ])('refuses forged selected %s', (attack) => {
    const raw = selection()
    const c: Record<string, unknown> = raw.command
    if (attack === 'owner') c.owner_id = child
    if (attack === 'child') c.command_id = id
    if (attack === 'hash') c.input_hash = inputHash
    if (attack === 'epoch') c.epoch = child
    if (attack === 'text')
      c.input = { ...raw.command.input, source: { channel: 'text', text: 'different' } }
    if (attack === 'kind') c.kind = 'meal.report'
    if (attack === 'before') c.admitted_at = '2026-11-05T12:00:00.000000999Z'
    if (attack === 'after') c.admitted_at = '2026-11-05T12:00:03.000001001Z'
    if (attack === 'extra') c.private_state = {}
    if (attack === 'decisionhash') raw.decision_hash = inputHash
    if (attack === 'question')
      (raw.decision as Record<string, unknown>).question = { field: 'record_kind', text: 'What?' }
    if (attack === 'missingcommand') (raw as Record<string, unknown>).command = null
    expect(() => parseConversationIntakeSelection(bound(), binding(), raw)).toThrow()
  })
  it('keeps clarification closed and never confuses routing with performed authority', () => {
    const decision = {
      schema: 'conversation.intake-routing.v1',
      kind: 'clarification_required',
      reason: 'ambiguous_source',
      question: { field: 'record_kind', text: 'Qual registro você realizou?' },
    }
    expect(parseConversationIntakeRoutingDecision(decision)).toEqual(decision)
    expect(() =>
      parseConversationIntakeRoutingDecision({ ...decision, question: undefined }),
    ).toThrow()
    expect(() =>
      parseConversationIntakeRoutingDecision({ ...decision, kind: 'not_reported' }),
    ).toThrow()
    expect(() =>
      parseConversationIntakeRoutingDecision({ ...decision, reason: 'UPPERCASE' }),
    ).toThrow()
  })
  it('validates meal child hash and explicit hint through the genuine meal binder', () => {
    const original = { ...input(), meal_type_hint: 'almoco' }
    const b = bindConversationIntake(owner, `cintake1:${id}`, original)
    expect(b.inputHash).toBe('e432358218a3c327d9271916704f264978f863af9bc2cd5397a11731b33aca63')
    const bind = {
      ...binding(),
      input_hash: 'e432358218a3c327d9271916704f264978f863af9bc2cd5397a11731b33aca63',
    }
    const raw: Record<string, unknown> = selection()
    raw.intake = bind
    raw.decision = {
      schema: 'conversation.intake-routing.v1',
      kind: 'meal.report',
      reason: 'performed_activity',
    }
    raw.decision_hash = '3aab4d8f7695e2b47fef5439d36d660f86070f60f51172979468952ef7018051'
    const typed = {
      command_protocol: 'conversation.command.v1',
      command_id: child,
      kind: 'meal.report',
      meal_type: 'almoco',
      source: input().source,
    }
    raw.command = {
      ...selection().command,
      kind: 'meal.report',
      input_hash: 'f40bc0fa3596a0ceb750d0452894bd8a75fbb3297c02a56d2b3df624acca1422',
      input: typed,
    }
    expect(parseConversationIntakeSelection(b, bind, raw).command?.input).toEqual(typed)
    raw.command = {
      ...selection().command,
      kind: 'meal.report',
      input_hash: '14831a9c99ddd74c801da1a16ce15f6bde5d6d0cb18d89648590c999e2360608',
      input: {
        command_protocol: 'conversation.command.v1',
        command_id: child,
        kind: 'meal.report',
        source: input().source,
      },
    }
    expect(() => parseConversationIntakeSelection(b, bind, raw)).toThrow()
  })
  it('nonselected decisions keep command null and never grant factual saved authority', () => {
    const raw = {
      ...selection(),
      decision: {
        schema: 'conversation.intake-routing.v1',
        kind: 'not_reported',
        reason: 'not_performed',
      },
      decision_hash: '384fa103fc2910057c9d15e397a15bdc1fe03827653858e0108b308d9ad2c3c3',
      command: null,
    }
    expect(parseConversationIntakeSelection(bound(), binding(), raw)).toEqual(raw)
    expect(() =>
      parseConversationIntakeSelection(bound(), binding(), {
        ...raw,
        command: selection().command,
      }),
    ).toThrow()
  })
  it('preserves permissible multiline source and rejects executable/non-JSON aliases before reading them', () => {
    const raw = { ...input(), source: { channel: 'text', text: 'fiz\n30 min\tde caminhada\r' } }
    expect(bindConversationIntake(owner, `cintake1:${id}`, raw).input.source).toEqual(raw.source)
    let reads = 0
    const poisoned = input()
    Object.defineProperty(poisoned.source, 'text', {
      enumerable: true,
      get() {
        reads++
        return 'secret'
      },
    })
    expect(() => bindConversationIntake(owner, `cintake1:${id}`, poisoned)).toThrow()
    expect(reads).toBe(0)
  })
  it.each([
    'valid',
    'foreign',
    'version',
    'kind',
    'processing-size',
    'context-size',
  ])('owned media capture %s stays neutral and bounded', (attack) => {
    const original = {
      intake_protocol: 'conversation.intake.v1',
      intake_id: id,
      source: {
        channel: 'media',
        media_asset_id: child,
        user_action: 'report_actual_record',
        caption: 'fiz 30 min de caminhada',
      },
    }
    const b = bindConversationIntake(owner, `cintake1:${id}`, original)
    const bind = { ...binding(), input_hash: b.inputHash }
    const media = {
      asset_id: child,
      owner_id: owner,
      kind: 'gym_photo',
      status: 'processed',
      processed_at: '2026-11-05T12:00:00.000002Z',
      updated_at: '2026-11-05T12:00:00.000002Z',
      context_text: 'x'.repeat(1100000),
      processing_result: { text: 'y'.repeat(900000) },
    }
    const context = { ...source().context, ...bind, source_input: original, media }
    if (attack === 'foreign') media.owner_id = id
    if (attack === 'version') media.updated_at = '2026-11-05T12:00:01.000001001Z'
    if (attack === 'kind') media.kind = 'unproved'
    if (attack === 'processing-size') media.processing_result.text = 'x'.repeat(1048576)
    if (attack === 'context-size') media.context_text = 'x'.repeat(2097152)
    if (attack === 'valid') {
      const value = parseConversationIntakeSource(b, bind, { source_hash: sourceHash, context })
      expect(value.context.media?.context_text?.length).toBe(1100000)
      expect(value.context.media?.kind).toBe('gym_photo')
      expect(() =>
        parseConversationIntakeSelection(b, bind, { ...selection(), intake: bind }),
      ).toThrow()
    } else
      expect(() =>
        parseConversationIntakeSource(b, bind, { source_hash: sourceHash, context }),
      ).toThrow()
  })
})
