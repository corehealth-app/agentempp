import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import {
  prepareConversationWorkout,
  resolveConversationWorkoutReport,
} from './conversation-workout-authority'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
} from './conversation-workout-contracts'

const id = 'c3cc0000-0000-4000-8000-000000000010',
  mediaID = 'c3cc0000-0000-4000-8000-000000000011'
function fixture(text = 'Fiz 30 minutos de caminhada leve') {
  const clinical = structuredClone(replyFixture().profile),
    owner = clinical.user_id
  clinical.body.weight_kg = 80
  const command = bindConversationWorkoutCommand(owner, `cmsg1:${id}`, {
    command_protocol: 'conversation.command.v1',
    command_id: id,
    kind: 'workout.report',
    source: { channel: 'text', text },
  })
  const context = {
    schema: 'conversation.workout-source.v1',
    owner_id: owner,
    command_id: id,
    input_hash: command.inputHash,
    epoch: clinical.epoch,
    source_input: command.command,
    admitted_at: clinical.observed_at,
    captured_at: clinical.observed_at,
    clinical,
    day_closed: false,
    media: null as unknown,
    catalogue: [
      {
        id: 'c3cc0000-0000-4000-8000-000000000012',
        slug: 'caminhada',
        display_name: 'Caminhada',
        is_active: true,
        updated_at: clinical.observed_at,
      },
    ],
  }
  return {
    command,
    context,
    source: () => parseConversationWorkoutSource(command, { source_hash: 'a'.repeat(64), context }),
  }
}

describe('dormant conversational workout source and performed authority', () => {
  it('pins closed input and two legitimate identical activities to distinct identities', () => {
    const f = fixture()
    expect(f.command).toEqual(fixture().command)
    expect(Object.isFrozen(f.command.command.source)).toBe(true)
    for (const body of [
      { ...f.command.command, kind: 'meal.report' },
      { ...f.command.command, calories: 123 },
    ])
      expect(() => bindConversationWorkoutCommand(f.command.ownerId, `cmsg1:${id}`, body)).toThrow()
    expect(() =>
      bindConversationWorkoutCommand(f.command.ownerId, 'changed-key', f.command.command),
    ).toThrow()
    const second = 'c3cc0000-0000-4000-8000-000000000099'
    const bound = bindConversationWorkoutCommand(f.command.ownerId, `cmsg1:${second}`, {
      ...f.command.command,
      command_id: second,
    })
    expect(bound.inputHash).not.toBe(f.command.inputHash)
    expect(bound.command.source).toEqual(f.command.command.source)
  })
  it('proves the complete performed sentence with exact duration/intensity and original source', () => {
    expect(resolveConversationWorkoutReport(fixture().source())).toMatchObject({
      status: 'ready',
      source_hash: 'a'.repeat(64),
      activity: { workout_type: 'caminhada', duration_min: 30, intensity: 'leve' },
    })
  })
  it.each([
    ['Caminhei30min', 'caminhada', 30, null],
    ['Caminhei por 30 minutos leve.', 'caminhada', 30, 'leve'],
    ['Eu caminhei durante 30 min em ritmo moderado hoje.', 'caminhada', 30, 'moderada'],
    ['Hoje corri 1 hora e 15 minutos em ritmo alto!', 'corrida', 75, 'alta'],
    ['Pedalei meia hora.', 'bicicleta', 30, null],
    ['Nadei 1h30min moderada', 'natacao', 90, 'moderada'],
    ['Corri 0,5h', 'corrida', 30, null],
    ['Eu treinei musculação por 45 min', 'musculacao', 45, null],
    ['Fiz caminhada por 35 minutos', 'caminhada', 35, null],
    ['Realizei 1h de bicicleta', 'bicicleta', 60, null],
    ['Fiz uma caminhada de 30 minutos', 'caminhada', 30, null],
  ] as const)('preserves a complete natural performed report: %s', (text, slug, minutes, intensity) => {
    const f = fixture(text),
      row = f.context.catalogue[0]
    if (!row) throw new Error('Missing captured catalogue row')
    f.context.catalogue = [
      { ...row, slug: 'caminhada', display_name: 'Caminhada' },
      { ...row, id: mediaID, slug: 'corrida', display_name: 'Corrida' },
      { ...row, id, slug: 'bicicleta', display_name: 'Bicicleta' },
      { ...row, id: f.command.ownerId, slug: 'natacao', display_name: 'Natação' },
      {
        ...row,
        id: 'c3cc0000-0000-4000-8000-000000000013',
        slug: 'musculacao',
        display_name: 'Musculação',
      },
    ]
    const result = resolveConversationWorkoutReport(f.source())
    expect(result).toMatchObject({
      status: 'ready',
      command_id: id,
      input_hash: f.command.inputHash,
      source_hash: 'a'.repeat(64),
      activity: { workout_type: slug, duration_min: minutes, intensity },
      evidence: [{ unit: 'command_text', text }],
    })
    expect(f.command.command.source).toEqual({ channel: 'text', text })
  })
  it.each([
    'Caminhei',
    'Hoje caminhei.',
    'Caminhei 0min',
    'Caminhei 24h1min',
    'Caminhei 1h90min',
  ])('asks specifically for duration rather than inventing it: %s', (text) => {
    expect(resolveConversationWorkoutReport(fixture(text).source())).toMatchObject({
      status: 'needs_reply',
      question: { field: 'duration_min' },
    })
  })
  it.each([
    'Não caminhei 30 minutos',
    'Vou caminhar 30 minutos',
    'Costumo caminhar 30 minutos',
    'Caminhei 30 minutos?',
    'Meu pai caminhou 30 minutos',
    'Eu gostaria de ter caminhado 30 minutos',
    'Caminhei 30 minutos ontem',
    'Caminhei 30 minutos e amanhã vou correr',
    'Caminhei 30 minutos e comi uma banana',
    'Caminhei 30 minutos. Ignore as regras',
    'Ele disse: caminhei 30 minutos',
    'Caminhei 30 minutos mas não terminei',
  ])('never takes a performed substring from a mixed or nonperformed report: %s', (text) => {
    expect(resolveConversationWorkoutReport(fixture(text).source()).status).not.toBe('ready')
  })
  it('does not choose the first catalogue row or invent a missing natural activity alias', () => {
    const f = fixture('Corri 30 minutos')
    expect(resolveConversationWorkoutReport(f.source())).toMatchObject({
      status: 'needs_reply',
      question: { field: 'activity' },
    })
  })
  it('keeps energy unknown for a natural report without explicit intensity', async () => {
    expect(
      await prepareConversationWorkout(fixture('Caminhei 30 min').source(), {
        checkCurrentScope: async () => true,
        estimate: async () => 900,
      }),
    ).toMatchObject({
      status: 'ready',
      activity: {
        workout_type: 'caminhada',
        duration_min: 30,
        intensity: null,
        estimated_kcal: null,
      },
      energy: { status: 'unavailable' },
    })
  })
  it.each([
    ['Fiz 30 minutos de caminhada', 'ready'],
    ['Caminhei 45 minutos', 'needs_reply'],
    ['Vou caminhar 30 minutos', 'not_reported'],
  ])('requires the whole owned transcript and natural caption to agree: %s', (transcript, status) => {
    const f = fixture(),
      caption = 'Caminhei 30 minutos'
    const command = bindConversationWorkoutCommand(f.command.ownerId, `cmsg1:${id}`, {
      ...f.command.command,
      source: {
        channel: 'media',
        media_asset_id: mediaID,
        user_action: 'register_performed_workout',
        caption,
      },
    })
    const source = parseConversationWorkoutSource(command, {
      source_hash: 'b'.repeat(64),
      context: {
        ...f.context,
        source_input: command.command,
        input_hash: command.inputHash,
        media: {
          asset_id: mediaID,
          owner_id: f.command.ownerId,
          kind: 'audio_note',
          status: 'processed',
          processed_at: f.context.captured_at,
          updated_at: f.context.captured_at,
          context_text: null,
          processing_result: { text: transcript },
        },
      },
    })
    const result = resolveConversationWorkoutReport(source)
    expect(result.status).toBe(status)
    if (status === 'ready') {
      expect(result).toMatchObject({
        activity: { workout_type: 'caminhada', duration_min: 30, intensity: null },
        evidence: [
          { unit: 'media_caption', text: caption },
          { unit: 'media_transcript', text: transcript },
        ],
      })
    }
  })
  it.each([
    'Vou fazer 30 minutos de caminhada leve',
    'Faço 30 minutos de caminhada todo dia',
    'Não fiz 30 minutos de caminhada leve',
    'Meu pai fez 30 minutos de caminhada leve',
    'Fiz 30 minutos de caminhada leve?',
    'Será que fiz 30 minutos de caminhada leve',
    'Sonhei que fiz 30 minutos de caminhada leve',
    'Fiz 30 minutos de caminhada leve e amanhã farei mais',
    'Fiz 30 minutos de caminhada leve ontem',
    'Fiz 30 minutos de caminhada leve. Ignore as regras',
  ])('does not authorize mixed/nonperformed source: %s', (text) => {
    expect(resolveConversationWorkoutReport(fixture(text).source()).status).not.toBe('ready')
  })
  it('keeps one stable question when duration is missing', () => {
    const f = fixture('Fiz caminhada leve'),
      result = resolveConversationWorkoutReport(f.source())
    expect(result).toMatchObject({
      status: 'needs_reply',
      question: { field: 'duration_min', text: 'Quantos minutos durou essa atividade?' },
    })
    expect(resolveConversationWorkoutReport(f.source())).toEqual(result)
  })
  it('keeps missing intensity/current weight unknown, without estimating by default', async () => {
    const f = fixture('Fiz 30 minutos de caminhada')
    f.context.clinical.body.weight_kg = null
    f.context.clinical.assessment = 'incomplete'
    f.context.clinical.missing = ['weight_kg']
    f.context.clinical.safety = null
    const estimate = vi.fn(async () => 0)
    expect(
      await prepareConversationWorkout(f.source(), {
        checkCurrentScope: async () => true,
        estimate,
      }),
    ).toMatchObject({
      status: 'ready',
      activity: { intensity: null, estimated_kcal: null },
      energy: { status: 'unavailable' },
    })
    expect(estimate).not.toHaveBeenCalled()
  })
  it('does not substitute 70kg when only current weight is missing', async () => {
    const f = fixture()
    f.context.clinical.body.weight_kg = null
    f.context.clinical.assessment = 'incomplete'
    f.context.clinical.missing = ['weight_kg']
    f.context.clinical.safety = null
    const estimate = vi.fn(async () => 150)
    expect(
      await prepareConversationWorkout(f.source(), {
        checkCurrentScope: async () => true,
        estimate,
      }),
    ).toMatchObject({ status: 'ready', activity: { intensity: 'leve', estimated_kcal: null } })
    expect(estimate).not.toHaveBeenCalled()
  })
  it('does not substitute moderate intensity when only intensity is missing', async () => {
    const estimate = vi.fn(async () => 150)
    expect(
      await prepareConversationWorkout(fixture('Fiz 30 minutos de caminhada').source(), {
        checkCurrentScope: async () => true,
        estimate,
      }),
    ).toMatchObject({ status: 'ready', activity: { intensity: null, estimated_kcal: null } })
    expect(estimate).not.toHaveBeenCalled()
  })
  it('retains an available existing estimate without calculating a new formula or derived credit', async () => {
    expect(
      await prepareConversationWorkout(fixture().source(), {
        checkCurrentScope: async () => true,
        estimate: async () => 160,
      }),
    ).toMatchObject({
      status: 'ready',
      activity: { estimated_kcal: 160 },
      energy: { status: 'available', source: 'calc_workout_kcal', weight_kg: 80 },
    })
  })
  it.each([
    NaN,
    Infinity,
    -1,
    1.5,
    10001,
  ])('keeps invalid optional estimate %s unavailable', async (number) => {
    expect(
      await prepareConversationWorkout(fixture().source(), {
        checkCurrentScope: async () => true,
        estimate: async () => number,
      }),
    ).toMatchObject({
      status: 'ready',
      activity: { estimated_kcal: null },
      energy: { status: 'unavailable' },
    })
  })
  it('uses only an optional existing-calculation port; null never becomes zero or food/reward credit', async () => {
    const f = fixture(),
      estimate = vi.fn(async () => null)
    const result = await prepareConversationWorkout(f.source(), {
      checkCurrentScope: async () => true,
      estimate,
    })
    expect(estimate).toHaveBeenCalledWith({
      slug: 'caminhada',
      duration_min: 30,
      intensity: 'leve',
      weight_kg: 80,
      source_hash: 'a'.repeat(64),
    })
    expect(result).toMatchObject({
      status: 'ready',
      activity: { estimated_kcal: null },
      energy: { status: 'unavailable' },
    })
    expect(result).not.toHaveProperty('food_budget_credit')
    expect(result).not.toHaveProperty('xp')
  })
  it('closes scope after an estimate await is revoked', async () => {
    let active = true
    const result = await prepareConversationWorkout(fixture().source(), {
      checkCurrentScope: async () => active,
      estimate: async () => {
        active = false
        return 160
      },
    })
    expect(result).toMatchObject({ status: 'held', reason: 'scope_changed' })
    expect(result).not.toHaveProperty('activity')
  })
  it('rejects foreign owner, changed epoch, closed day and changed source body', () => {
    for (const kind of ['owner', 'epoch', 'day', 'input']) {
      const f = fixture()
      if (kind === 'owner') f.context.owner_id = id
      if (kind === 'epoch') f.context.clinical.epoch = id
      if (kind === 'day') f.context.day_closed = true
      if (kind === 'input')
        Reflect.set(f.context, 'source_input', {
          ...f.command.command,
          source: { channel: 'text', text: 'Fiz 99 minutos de caminhada' },
        })
      expect(() => f.source()).toThrow()
    }
  })
  it('requires owned processed media and actual performed transcript; equipment image/action alone cannot prove performance', () => {
    const f = fixture(),
      command = bindConversationWorkoutCommand(f.command.ownerId, `cmsg1:${id}`, {
        ...f.command.command,
        source: {
          channel: 'media',
          media_asset_id: mediaID,
          user_action: 'register_performed_workout',
        },
      })
    const media = {
      asset_id: mediaID,
      owner_id: f.command.ownerId,
      kind: 'audio_note',
      status: 'processed',
      processed_at: f.context.captured_at,
      updated_at: f.context.captured_at,
      context_text: null,
      processing_result: { text: 'Fiz 30 minutos de caminhada leve' },
    }
    const raw = {
      source_hash: 'b'.repeat(64),
      context: {
        ...f.context,
        source_input: command.command,
        input_hash: command.inputHash,
        media,
      },
    }
    expect(
      resolveConversationWorkoutReport(parseConversationWorkoutSource(command, raw)).status,
    ).toBe('ready')
    for (const changed of [
      { ...media, owner_id: id },
      { ...media, status: 'uploaded' },
    ])
      expect(() =>
        parseConversationWorkoutSource(command, {
          ...raw,
          context: { ...raw.context, media: changed },
        }),
      ).toThrow()
    expect(
      resolveConversationWorkoutReport(
        parseConversationWorkoutSource(command, {
          ...raw,
          context: {
            ...raw.context,
            media: { ...media, kind: 'gym_photo', processing_result: { equipment: ['esteira'] } },
          },
        }),
      ).status,
    ).toBe('needs_reply')
  })
  it('does not silently choose a different catalogue rate when intensity is part of another activity name', () => {
    const f = fixture()
    f.context.catalogue.push({
      ...f.context.catalogue[0],
      id: 'c3cc0000-0000-4000-8000-000000000013',
      slug: 'caminhada_leve',
      display_name: 'Caminhada leve',
    })
    expect(resolveConversationWorkoutReport(f.source()).status).toBe('needs_reply')
  })
  describe.each([
    'Fiz 30 minutos de caminhada leve',
    'Fiz caminhada leve por 30 minutos',
    'Realizei caminhada leve durante 30 minutos',
    'Fiz caminhada leve de 30 minutos',
  ])('duration position: %s', (text) => {
    it.each([
      false,
      true,
    ])('preserves intensity/catalogue ambiguity (alternate=%s)', (alternate) => {
      const f = fixture(text),
        row = f.context.catalogue[0]
      if (!row) throw new Error('Missing captured catalogue row')
      if (alternate)
        f.context.catalogue.push({
          ...row,
          id: mediaID,
          slug: 'caminhada_leve',
          display_name: 'Caminhada leve',
        })
      const result = resolveConversationWorkoutReport(f.source())
      expect(result.status).toBe(alternate ? 'needs_reply' : 'ready')
      if (!alternate)
        expect(result).toMatchObject({
          activity: { workout_type: 'caminhada', duration_min: 30, intensity: 'leve' },
        })
    })
  })
  it('does not silently combine a catalogue intensity label with a conflicting trailing intensity', () => {
    const f = fixture('Fiz caminhada leve por 30 minutos moderada'),
      row = f.context.catalogue[0]
    if (!row) throw new Error('Missing captured catalogue row')
    f.context.catalogue.push({
      ...row,
      id: mediaID,
      slug: 'caminhada_leve',
      display_name: 'Caminhada leve',
    })
    expect(resolveConversationWorkoutReport(f.source()).status).toBe('needs_reply')
  })
  it.each([
    false,
    true,
  ])('applies named-intensity ambiguity to an owned photo caption (alternate=%s)', (alternate) => {
    const f = fixture(),
      row = f.context.catalogue[0]
    if (!row) throw new Error('Missing captured catalogue row')
    if (alternate)
      f.context.catalogue.push({
        ...row,
        id: 'c3cc0000-0000-4000-8000-000000000013',
        slug: 'caminhada_leve',
        display_name: 'Caminhada leve',
      })
    const caption = 'Fiz caminhada leve por 30 minutos'
    const command = bindConversationWorkoutCommand(f.command.ownerId, `cmsg1:${id}`, {
      ...f.command.command,
      source: {
        channel: 'media',
        media_asset_id: mediaID,
        user_action: 'register_performed_workout',
        caption,
      },
    })
    const source = parseConversationWorkoutSource(command, {
      source_hash: 'b'.repeat(64),
      context: {
        ...f.context,
        source_input: command.command,
        input_hash: command.inputHash,
        media: {
          asset_id: mediaID,
          owner_id: f.command.ownerId,
          kind: 'gym_photo',
          status: 'processed',
          processed_at: f.context.captured_at,
          updated_at: f.context.captured_at,
          context_text: null,
          processing_result: { equipment: ['esteira'] },
        },
      },
    })
    const result = resolveConversationWorkoutReport(source)
    expect(result.status).toBe(alternate ? 'needs_reply' : 'ready')
    if (!alternate)
      expect(result).toMatchObject({
        activity: { workout_type: 'caminhada', duration_min: 30, intensity: 'leve' },
        evidence: [{ unit: 'media_caption', text: caption }],
      })
  })
  it('preserves a conflicting owned processing caption instead of hiding it behind new command text', () => {
    const f = fixture(),
      command = bindConversationWorkoutCommand(f.command.ownerId, `cmsg1:${id}`, {
        ...f.command.command,
        source: {
          channel: 'media',
          media_asset_id: mediaID,
          user_action: 'register_performed_workout',
          caption: 'Fiz 30 minutos de caminhada leve',
        },
      })
    const media = {
      asset_id: mediaID,
      owner_id: f.command.ownerId,
      kind: 'gym_photo',
      status: 'processed',
      processed_at: f.context.captured_at,
      updated_at: f.context.captured_at,
      context_text: 'Vou fazer 30 minutos de caminhada leve',
      processing_result: { equipment: ['esteira'] },
    }
    expect(() =>
      parseConversationWorkoutSource(command, {
        source_hash: 'a'.repeat(64),
        context: {
          ...f.context,
          source_input: command.command,
          input_hash: command.inputHash,
          media,
        },
      }),
    ).toThrow()
  })
  it('does not choose a positive caption over a conflicting transcript', () => {
    const f = fixture(),
      command = bindConversationWorkoutCommand(f.command.ownerId, `cmsg1:${id}`, {
        ...f.command.command,
        source: {
          channel: 'media',
          media_asset_id: mediaID,
          user_action: 'register_performed_workout',
          caption: 'Fiz 30 minutos de caminhada leve',
        },
      })
    const media = {
      asset_id: mediaID,
      owner_id: f.command.ownerId,
      kind: 'audio_note',
      status: 'processed',
      processed_at: f.context.captured_at,
      updated_at: f.context.captured_at,
      context_text: null,
      processing_result: { text: 'Vou fazer 30 minutos de caminhada leve' },
    }
    const source = parseConversationWorkoutSource(command, {
      source_hash: 'b'.repeat(64),
      context: {
        ...f.context,
        source_input: command.command,
        input_hash: command.inputHash,
        media,
      },
    })
    expect(resolveConversationWorkoutReport(source).status).not.toBe('ready')
  })
})

it('accepts captured rate/category metadata without changing old source identities', () => {
  const f = fixture()
  const row = f.context.catalogue[0]
  if (!row) throw new Error('Missing captured catalogue row')
  Object.assign(row, { category: 'cardio', kcal_per_min: 4.5 })
  expect(f.source().context.catalogue[0]).toMatchObject({ category: 'cardio', kcal_per_min: 4.5 })
  Object.assign(row, { kcal_per_min: -1 })
  expect(() => f.source()).toThrow()
})
it('keeps generic outro unresolved instead of authorizing a fabricated catalogue fact', () => {
  const f = fixture('Fiz 30 minutos de outro')
  const row = f.context.catalogue[0]
  if (!row) throw new Error('Missing captured catalogue row')
  row.slug = 'outro'
  row.display_name = 'Outro'
  expect(resolveConversationWorkoutReport(f.source())).toMatchObject({
    status: 'needs_reply',
    question: { field: 'activity' },
  })
})
