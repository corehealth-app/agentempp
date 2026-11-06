import { describe, expect, it } from 'vitest'
import {
  bindConversationCommand,
  conversationMealCommandSchema,
} from './conversation-command-contracts'
import {
  bindConversationIntake,
  parseConversationIntakeSelection,
} from './conversation-intake-contracts'
import {
  bindConversationWorkoutCommand,
  conversationWorkoutCommandSchema,
  workoutDigest,
} from './conversation-workout-contracts'

const owner = 'c3cc0000-0000-4000-8000-000000000001',
  intakeID = 'c3cc0000-0000-4000-8000-000000000044',
  childID = 'c3cc0000-0000-4000-8000-000000000045',
  assetID = 'c3cc0000-0000-4000-8000-000000000046',
  epoch = 'c3cc0000-0000-4000-8000-000000000047',
  claimID = 'c3cc0000-0000-4000-8000-000000000048'

function fixture(kind: 'meal.report' | 'workout.report' = 'meal.report') {
  const input = {
      intake_protocol: 'conversation.intake.v1',
      intake_id: intakeID,
      source: {
        channel: 'media',
        media_asset_id: assetID,
        user_action: 'report_actual_record',
        caption: kind === 'meal.report' ? 'Comi este almoço.' : 'Fiz 30 minutos de caminhada.',
      },
    },
    parent = bindConversationIntake(owner, `cintake1:${intakeID}`, input),
    binding = {
      owner_id: owner,
      intake_id: intakeID,
      input_hash: parent.inputHash,
      epoch,
      admitted_at: '2026-11-06T10:00:00.000001Z',
    },
    decision = { schema: 'conversation.intake-routing.v1', kind, reason: 'actual_report' },
    origin = {
      schema: 'conversation.intake-media-origin.v1',
      intake_id: intakeID,
      input_hash: parent.inputHash,
      source_hash: 'a'.repeat(64),
      epoch,
      claim_id: claimID,
      decision_hash: workoutDigest(decision),
    },
    child = {
      command_protocol: 'conversation.command.v1',
      command_id: childID,
      kind,
      source: input.source,
      intake_origin: origin,
    }
  const projection = {
    schema: 'conversation.intake-media-projection.v1',
    origin,
    media: {
      asset_id: assetID,
      owner_id: owner,
      kind: kind === 'meal.report' ? 'meal_photo' : 'audio_note',
      processed_at: '2026-11-06T09:59:00Z',
      updated_at: '2026-11-06T09:59:00Z',
      processing_hash: 'b'.repeat(64),
    },
    child_input_hash: workoutDigest(child),
  }
  const selection = {
    schema: 'conversation.intake-selection.v2',
    intake: binding,
    source_hash: origin.source_hash,
    decision_hash: origin.decision_hash,
    decision,
    selected_at: '2026-11-06T10:00:00.000004Z',
    command: {
      kind,
      owner_id: owner,
      command_id: childID,
      input_hash: projection.child_input_hash,
      epoch,
      admitted_at: '2026-11-06T10:00:00.000003Z',
      input: child,
    },
    media_projection: projection,
  }
  return { parent, binding, origin, child, projection, selection }
}
describe('internal neutral-media execution lineage', () => {
  it.each([
    'meal.report',
    'workout.report',
  ] as const)('preserves original neutral action and origin in the real %s execution binder', (kind) => {
    const f = fixture(kind),
      bound =
        kind === 'meal.report'
          ? bindConversationCommand(owner, `cmsg1:${childID}`, f.child)
          : bindConversationWorkoutCommand(owner, `cmsg1:${childID}`, f.child)
    expect(bound.command).toEqual(f.child)
    expect(bound.command.source).toEqual(f.parent.input.source)
    expect(bound.inputHash).toBe(f.projection.child_input_hash)
    expect(JSON.stringify(bound.command)).not.toMatch(
      /register_consumed_meal|register_performed_workout/,
    )
  })
  it.each([
    'meal.report',
    'workout.report',
  ] as const)('does not expose the internal alternative through the old public %s body schema', (kind) => {
    const f = fixture(kind)
    expect(
      (kind === 'meal.report'
        ? conversationMealCommandSchema
        : conversationWorkoutCommandSchema
      ).safeParse(f.child).success,
    ).toBe(false)
  })
  it.each([
    'meal.report',
    'workout.report',
  ] as const)('decodes the sealed %s media selection only with the original parent, source and child binding', (kind) => {
    const f = fixture(kind),
      parsed = parseConversationIntakeSelection(f.parent, f.binding, f.selection)
    expect(parsed.schema).toBe('conversation.intake-selection.v2')
    expect(parsed.command?.input).toEqual(f.child)
    expect(parsed).toHaveProperty('media_projection', f.projection)
  })
  it.each([
    'intake_id',
    'input_hash',
    'source_hash',
    'epoch',
    'decision_hash',
  ] as const)('refuses a projected origin with changed %s even if the child hash is recomputed', (field) => {
    const f = fixture(),
      changed = structuredClone(f.selection)
    changed.command.input.intake_origin[field] =
      field.endsWith('id') || field === 'epoch' ? owner : 'c'.repeat(64)
    changed.media_projection.origin = changed.command.input.intake_origin
    changed.command.input_hash = workoutDigest(changed.command.input)
    changed.media_projection.child_input_hash = changed.command.input_hash
    expect(() => parseConversationIntakeSelection(f.parent, f.binding, changed)).toThrow()
  })
  it('detaches and freezes every nested origin reference after binding', () => {
    const f = fixture(),
      command = bindConversationCommand(owner, `cmsg1:${childID}`, f.selection.command.input)
    expect(Object.isFrozen(command.command)).toBe(true)
    expect(Object.isFrozen(command.command.source)).toBe(true)
    expect(
      'intake_origin' in command.command && Object.isFrozen(command.command.intake_origin),
    ).toBe(true)
  })
  it('refuses another asset or owner instead of treating the projection as a media capability', () => {
    const f = fixture(),
      changed = structuredClone(f.selection)
    changed.media_projection.media.asset_id = childID
    expect(() => parseConversationIntakeSelection(f.parent, f.binding, changed)).toThrow()
    changed.media_projection.media.asset_id = assetID
    changed.media_projection.media.owner_id = childID
    expect(() => parseConversationIntakeSelection(f.parent, f.binding, changed)).toThrow()
  })
  it('refuses a media projection disguised as the historical text-only selection version', () => {
    const f = fixture()
    expect(() =>
      parseConversationIntakeSelection(f.parent, f.binding, {
        ...f.selection,
        schema: 'conversation.intake-selection.v1',
      }),
    ).toThrow()
  })
})
