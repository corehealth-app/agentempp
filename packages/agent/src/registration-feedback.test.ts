import { describe, expect, it } from 'vitest'
import { FLOW_CURATED_PHRASE_CATALOG } from './flow-curated-phrase-catalog.js'
import {
  createFlowPhraseRotationState,
  prepareFlowStatusPhraseReply,
} from './flow-curated-phrases.js'
import {
  prepareRegistrationFeedback,
  type RegistrationFeedbackInput,
} from './registration-feedback.js'

function input(overrides: Partial<RegistrationFeedbackInput> = {}): RegistrationFeedbackInput {
  return {
    userId: 'qa-A',
    registrationId: 'registration-1',
    locale: 'pt-BR',
    registration: {
      kind: 'meal',
      status: 'confirmed',
      mealKind: 'cafe',
      items: [{ food_name: 'iogurte natural', kcal: 435, protein_g: 42, carbs_g: 49, fat_g: 5 }],
    },
    day: {
      local_date: '2026-10-24',
      current_protocol: 'recomposicao',
      consumed: { calories_kcal: 1785, protein_g: 126, carbs_g: 200, fat_g: 50 },
      targets: { calories_kcal: 2400, protein_g: 150 },
      remaining_food_kcal: 615,
      food_excess_kcal: 0,
      exercise_kcal: 504,
    },
    ...overrides,
  }
}
function requiredDay(request: RegistrationFeedbackInput) {
  if (request.day === null) throw new Error('Fixture day missing')
  return request.day
}
const text = (result: ReturnType<typeof prepareRegistrationFeedback>) =>
  result.feedback.lines.map((row) => row.text).join('\n')

describe('C13: confirmed registration feedback, approved facts and phrases', () => {
  it('accepts the official consumed source and projects only its declared public fields', () => {
    const request = input()
    const day = requiredDay(request)
    const actual = {
      ...day,
      pending_actions: { registrations: ['private-pending-sentinel'] },
      routine_items: ['private-routine-sentinel'],
      consumed: { ...day.consumed, source: 'daily_snapshot' as const },
      targets: { ...day.targets, source: 'mixed' as const },
    }
    const result = prepareRegistrationFeedback({ ...request, day: actual }, null)
    expect(result.feedback.day).toStrictEqual({
      ...day,
      calorie_percentage: 74.4,
      protein_percentage: 84,
    })
    expect(JSON.stringify(result.feedback)).not.toContain('sentinel')
    expect(result.feedback.day?.consumed).not.toHaveProperty('source')
    expect(result.feedback.day?.targets).not.toHaveProperty('source')
  })
  it('renders the actual meal totals and one-decimal day goldens without adding exercise to food', () => {
    const result = prepareRegistrationFeedback(input(), null)
    expect(result.feedback.meal_totals).toStrictEqual({
      kcal: 435,
      protein_g: 42,
      carbs_g: 49,
      fat_g: 5,
    })
    expect(text(result)).toContain('435 kcal | Proteína: 42 g | Carboidratos: 49 g | Gorduras: 5 g')
    expect(text(result)).toContain('Limite calórico atingido: 74,4% (1.785 / 2.400 kcal)')
    expect(text(result)).toContain('Proteína: 84,0% (126 / 150 g)')
    expect(text(result)).toContain('Restam 615 kcal para comida.')
    expect(text(result)).not.toContain('1.119')
    expect(result.feedback.food_comment).toBeTruthy()
    expect(result.feedback.incentive).toBeTruthy()
    expect(result.receipts).toHaveLength(2)
    expect(result.nextCursor.ordinal).toBe(2)
  })
  it.each([
    ['ganho_massa', 2900, 'Meta calórica atingida: 61,6% (1.785 / 2.900 kcal)'],
    ['manutencao', 2500, 'Meta diária utilizada: 71,4% (1.785 / 2.500 kcal)'],
  ] as const)('uses the protocol label for %s and preserves correct rounding', (protocol, target, golden) => {
    const request = input()
    request.day = {
      ...requiredDay(request),
      current_protocol: protocol,
      targets: { calories_kcal: target, protein_g: 150 },
    }
    const result = prepareRegistrationFeedback(request, null)
    expect(text(result)).toContain(golden)
    expect(text(result)).not.toMatch(/7[.,]700|14 dias|hipertrofia|61,5%/u)
  })
  it('shows numbers and incentive, with no invented food comment for an unmatched food', () => {
    const result = prepareRegistrationFeedback(
      input({
        registration: {
          kind: 'meal',
          status: 'confirmed',
          mealKind: 'almoco',
          items: [
            {
              food_name: 'alimento sintético sem frase aprovada',
              kcal: 100,
              protein_g: 10,
              carbs_g: 5,
              fat_g: 3,
            },
          ],
        },
      }),
      null,
    )
    expect(result.feedback.food_comment).toBeNull()
    expect(result.feedback.incentive).toBeTruthy()
    expect(result.receipts[0]?.selection.reason).toBe('no_food_match')
    expect(result.nextCursor.ordinal).toBe(1)
  })
  it('workout has day numbers and an approved incentive, no made-up meal total', () => {
    const result = prepareRegistrationFeedback(
      input({ registration: { kind: 'workout', status: 'confirmed' } }),
      null,
    )
    expect(result.feedback.meal_totals).toBeNull()
    expect(result.feedback.food_comment).toBeNull()
    expect(result.feedback.incentive).toBeTruthy()
    expect(result.receipts).toHaveLength(1)
    expect(text(result)).toContain('74,4%')
  })
  it('does not translate the Portuguese phrase bank into English', () => {
    const result = prepareRegistrationFeedback(input({ locale: 'en-US' }), null)
    expect(text(result)).toContain('Calorie limit reached: 74.4% (1,785 / 2,400 kcal)')
    expect(text(result)).toContain('Protein: 84.0% (126 / 150 g)')
    expect(result.feedback.food_comment).toBeNull()
    expect(result.feedback.incentive).toBeNull()
    expect(result.nextCursor.ordinal).toBe(0)
    expect(result.receipts.every((row) => row.selection.reason === 'unsupported_language')).toBe(
      true,
    )
  })
  it('does not turn absent or zero targets into percentages or invent a day from no data', () => {
    const request = input()
    request.day = { ...requiredDay(request), targets: { calories_kcal: null, protein_g: null } }
    const result = prepareRegistrationFeedback(request, null)
    expect(text(result)).toContain('Meta indisponível')
    expect(text(result)).not.toMatch(/Infinity|NaN|0,0%/u)
    expect(text(prepareRegistrationFeedback(input({ day: null }), null))).toContain(
      'Os dados deste dia estão indisponíveis.',
    )
    expect(prepareRegistrationFeedback(input({ day: null }), null).feedback.day).toBeNull()
    expect(() =>
      prepareRegistrationFeedback(
        {
          ...request,
          day: { ...requiredDay(request), targets: { calories_kcal: 0, protein_g: 150 } },
        },
        null,
      ),
    ).toThrow()
  })
  it('does not call partial food credit a new allowance, and shows excess explicitly', () => {
    const request = input()
    request.day = { ...requiredDay(request), remaining_food_kcal: 0, food_excess_kcal: 115 }
    expect(text(prepareRegistrationFeedback(request, null))).toContain(
      'Excedente: 115 kcal de comida.',
    )
  })
  it('uses one shared cursor with Flow status; the next workout cannot repeat its incentive', () => {
    const status = prepareFlowStatusPhraseReply(
      {
        userId: 'qa-A',
        eventKey: 'status-1',
        locale: 'pt-BR',
        kind: 'incentive',
        slot: 'any',
        statusText: 'Status do dia',
        authority: {
          currentProtocol: 'recomposicao',
          dailyTargets: { calories_target: 2400, protein_target: 150 },
        },
      },
      null,
    )
    const workout = prepareRegistrationFeedback(
      input({ registration: { kind: 'workout', status: 'confirmed' } }),
      status.nextCursor,
    )
    expect(workout.feedback.incentive).not.toBe(status.receipt.selection.phrase)
    expect(workout.nextCursor.ordinal).toBe(2)
    expect(status.nextCursor.ordinal).toBe(1)
  })
  it('is deterministic without mutating its supplied shared state; receipt keys are registration scoped', () => {
    const { replayByEventKey: _, ...cursor } = createFlowPhraseRotationState(
      'qa-A',
      FLOW_CURATED_PHRASE_CATALOG.version,
    )
    const before = structuredClone(cursor)
    const first = prepareRegistrationFeedback(input(), cursor)
    expect(prepareRegistrationFeedback(input(), cursor)).toStrictEqual(first)
    expect(cursor).toStrictEqual(before)
    expect(first.receipts.map((row) => row.eventKey)).toStrictEqual([
      'mobile_registration/qa-A/registration-1/food',
      'mobile_registration/qa-A/registration-1/incentive',
    ])
  })
  it('does not repurpose content from another owner, stale catalog, or malformed cursor', () => {
    const { replayByEventKey: _, ...cursor } = createFlowPhraseRotationState(
      'qa-B',
      FLOW_CURATED_PHRASE_CATALOG.version,
    )
    expect(() => prepareRegistrationFeedback(input(), cursor)).toThrow()
    expect(() =>
      prepareRegistrationFeedback(input(), {
        ...cursor,
        userId: 'qa-A',
        catalogVersion: 'obsolete',
      }),
    ).toThrow()
    expect(() =>
      prepareRegistrationFeedback(input(), {
        ...cursor,
        userId: 'qa-A',
        ordinal: 1,
        lastTextKey: null,
      }),
    ).toThrow()
  })
  it('rejects unconfirmed registrations and invalid numeric facts before selecting', () => {
    for (const status of ['pending', 'cancelled', 'expired']) {
      expect(() =>
        prepareRegistrationFeedback(
          input({ registration: { kind: 'workout', status: status as 'confirmed' } }),
          null,
        ),
      ).toThrow()
    }
    const request = input()
    request.day = {
      ...requiredDay(request),
      consumed: { ...requiredDay(request).consumed, protein_g: Number.NaN },
    }
    expect(() => prepareRegistrationFeedback(request, null)).toThrow()
  })
  it('projects legacy names through the public-name boundary on selected phrase text', () => {
    // Synthetic policy fixture, never published as clinical/approved content.
    const catalog = {
      version: 'synthetic-name-policy',
      sources: [],
      entries: [
        {
          id: 'engagement:000',
          kind: 'incentive' as const,
          locale: 'pt-BR' as const,
          sourceText: 'Sou o Dr. Roberto Menescal. Seguimos o método MPP.',
          foodAliases: [],
          sourceSlot: 'any' as const,
          source: { file: 'synthetic-name-policy-only', phraseIndex: 0 },
        },
      ],
    }
    const result = prepareRegistrationFeedback(
      input({ registration: { kind: 'workout', status: 'confirmed' } }),
      null,
      catalog,
    )
    expect(result.feedback.incentive).toBe('Sou o Flow. Seguimos o método Performe AI.')
    expect(result.feedback.day?.calorie_percentage).toBe(74.4)
    expect(result.feedback.day?.protein_percentage).toBe(84)
  })
})
