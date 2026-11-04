import { bindConversationCommand } from '../conversation-command-contracts'

export const writerOwner = '10000000-0000-4000-8000-000000000001'
export const writerCommandId = '10000000-0000-4000-8000-000000000002'
export const writerEpoch = '10000000-0000-4000-8000-000000000003'
export function writerCommand() {
  return bindConversationCommand(writerOwner, `cmsg1:${writerCommandId}`, {
    command_protocol: 'conversation.command.v1',
    command_id: writerCommandId,
    kind: 'meal.report',
    meal_type: 'almoco',
    source: { channel: 'text', text: 'Comi arroz 100 g' },
  })
}
export function writerBinding() {
  return {
    owner_id: writerOwner,
    command_id: writerCommandId,
    input_hash: writerCommand().inputHash,
    command_protocol: 'conversation.command.v1',
    kind: 'meal.report',
    epoch: writerEpoch,
    admitted_at: '2026-11-04T12:00:00.000001Z',
  }
}
export function writerSource() {
  return {
    sourceHash: 'a'.repeat(64),
    capturedAt: '2026-11-04T12:00:00.000002Z',
    epoch: writerEpoch,
    context: {
      schema: 'conversation.meal-source.v1' as const,
      owner_id: writerOwner,
      command_id: writerCommandId,
      input_hash: writerCommand().inputHash,
      epoch: writerEpoch,
      source_input: writerCommand().command,
      source_units: ['command_text' as const],
      source_evidence: {},
      media: null,
      catalog: { epoch: writerEpoch, revision: '2' },
      owner: {
        timezone: 'America/Sao_Paulo',
        locale: 'pt-BR',
        country: 'BR',
        country_confirmed: true,
      },
      clinical: { policy: { status: 'available' }, safety: { reasons: [] } },
      day: {
        date: '2026-11-04',
        day_closed: false,
        calories_target: null,
        protein_target: null,
        current_protocol: null,
        target_revision: '0',
        calorie_origin: null,
      },
    },
  }
}
export function writerResolved() {
  return {
    schema: 'conversation.meal-resolved.v1',
    input_hash: writerCommand().inputHash,
    source_hash: 'a'.repeat(64),
    meal_type: 'almoco',
    semantic_proof: {
      schema: 'conversation.meal-semantic.v1',
      decision: 'consumed_meal',
      input_hash: writerCommand().inputHash,
      source_hash: 'a'.repeat(64),
      complete_source: true,
      source_units: ['command_text' as const],
      input_count: 1,
    },
    items: [
      {
        name: 'Arroz branco cozido',
        food_db_id: 1 as number | null,
        nutrition_source: 'canonical_exact',
        quantity_g: 100,
        kcal: 128,
        protein_g: 2.5,
        carbs_g: 28.1,
        fat_g: 0.2,
        confidence: 1,
        input_indexes: [0],
        quantity_basis: 'stated',
        display_qty: null,
        display_unit: null,
      },
    ],
    totals: { kcal: 128, protein_g: 2.5, carbs_g: 28.1, fat_g: 0.2 },
    preparation_annotations: [] as {
      schema: string
      kind: string
      input_indexes: number[]
      food_name: string
      policy: string
      reference_id: string
    }[],
    source_receipts: [] as { id: string; hash: string }[],
  }
}
export function writerReceipt() {
  return {
    schema: 'conversation.meal-effect.v1',
    owner_id: writerOwner,
    command_id: writerCommandId,
    input_hash: writerCommand().inputHash,
    registration_id: '10000000-0000-4000-8000-000000000004',
    provider_key: `conversation.meal/${writerOwner}/${writerCommandId}`,
    meal_type: 'almoco',
    local_date: '2026-11-04',
    timezone: 'America/Sao_Paulo',
    consumed_at: '2026-11-04T12:00:01.000004Z',
    log_ids: ['10000000-0000-4000-8000-000000000005'],
    effect_version: `cmeal1:${'b'.repeat(64)}`,
  }
}
export function writerPrepared() {
  const s = writerSource()
  return {
    action: 'available',
    command: writerBinding(),
    source: { source_hash: s.sourceHash, captured_at: s.capturedAt, context: s.context },
    resolved: {
      resolved_hash: 'c'.repeat(64),
      prepared_at: '2026-11-04T12:00:00.000003Z',
      resolved: writerResolved(),
    },
    receipt: null as unknown,
  }
}
