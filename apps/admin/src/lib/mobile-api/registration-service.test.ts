import type { MealCalcResult } from '@mpp/agent'
import { describe, expect, it } from 'vitest'
import {
  buildMealPendingProposal,
  cancelRegistration,
  confirmRegistration,
  proposeRegistration,
} from './registration-service'
import { sanitizePendingProposal } from './read-model'

describe('mobile registration service', () => {
  it('rejects meal calculation until the patient confirms their country', async () => {
    const supabase = {
      from() {
        throw new Error('nutrition lookup must not run before country confirmation')
      },
    }

    await expect(
      proposeRegistration(
        supabase as never,
        {
          userId: 'patient-1',
          patient: {
            country: 'BR',
            countryConfirmed: false,
            timezone: 'America/New_York',
          },
        } as never,
        {
          kind: 'meal',
          meal_type: 'jantar',
          items: [{ food_name: 'arroz branco', quantity_g: 100 }],
        },
        'mobile-request-country-1',
      ),
    ).rejects.toMatchObject({
      status: 409,
      code: 'country_confirmation_required',
    })
  })

  it('builds a server-calculated meal proposal without internal match details', () => {
    const calculation: MealCalcResult = {
      items: [
        {
          food_name: 'arroz branco',
          matched_taco_name: 'Arroz, integral, cozido',
          matched_taco_id: 42,
          quantity_g: 100,
          kcal: 124,
          protein_g: 2.6,
          carbs_g: 25.8,
          fat_g: 1,
          fiber_g: 2.7,
          similarity: 0.91,
          source: 'canonical_exact',
          display_qty: 100,
          display_unit: 'g',
        },
      ],
      totals: { kcal: 124, protein_g: 2.6, carbs_g: 25.8, fat_g: 1, fiber_g: 2.7 },
      warnings: [],
      user_warnings: [],
      audit_warnings: ['internal only'],
    }

    expect(
      buildMealPendingProposal(
        {
          kind: 'meal',
          meal_type: 'almoco',
          items: [{ food_name: 'arroz branco', quantity_g: 100 }],
        },
        calculation,
        {
          requestKey: 'mobile-request-0001',
          timestamp: '2026-07-20T16:00:00.000Z',
          timezone: 'America/New_York',
          localDate: '2026-07-20',
        },
      ),
    ).toMatchObject({
      kind: 'meal',
      mealType: 'almoco',
      sourceContentType: 'mobile',
      source_provider_message_id: 'mobile-request-0001',
      // Defect B (iPhone, staging, 2026-10-04): the confirm registers a
      // proposal the app built as a new record only when it carries this.
      registration_origin: 'mobile_app',
      replace: false,
      items: [
        {
          name: 'arroz branco',
          food_db_id: 42,
          nutrition_source: 'canonical_exact',
          kcal: 124,
        },
      ],
      totals: { kcal: 124, protein_g: 2.6, carbs_g: 25.8, fat_g: 1 },
      userWarnings: [],
    })
  })

  it('writes the app origin only when told the pending is one the app created', () => {
    const calculation: MealCalcResult = {
      items: [
        {
          food_name: 'arroz branco',
          matched_taco_name: 'Arroz, integral, cozido',
          matched_taco_id: 42,
          quantity_g: 100,
          kcal: 124,
          protein_g: 2.6,
          carbs_g: 25.8,
          fat_g: 1,
          fiber_g: 2.7,
          similarity: 0.91,
          source: 'canonical_exact',
        },
      ],
      totals: { kcal: 124, protein_g: 2.6, carbs_g: 25.8, fat_g: 1, fiber_g: 2.7 },
      warnings: [],
      user_warnings: [],
      audit_warnings: [],
    }
    const build = (origin: 'mobile_app' | null) =>
      buildMealPendingProposal(
        {
          kind: 'meal',
          meal_type: 'almoco',
          items: [{ food_name: 'arroz branco', quantity_g: 100 }],
        },
        calculation,
        {
          requestKey: 'mobile-request-0002',
          timestamp: '2026-07-20T16:00:00.000Z',
          timezone: 'America/New_York',
          localDate: '2026-07-20',
        },
        origin,
      )

    expect(build('mobile_app')).toMatchObject({ registration_origin: 'mobile_app' })
    // The edit of a pending created on WhatsApp: no key at all, so the confirm
    // does not take it for a proposal of the app.
    expect(build(null)).not.toHaveProperty('registration_origin')
    expect(build(null)).toMatchObject({ replace: false, mealType: 'almoco' })
  })

  it('scopes registration lookup to the authenticated patient', async () => {
    const filters: Array<[string, string]> = []
    const builder = {
      select() {
        return this
      },
      eq(column: string, value: string) {
        filters.push([column, value])
        return this
      },
      async maybeSingle() {
        return {
          data: {
            id: 'registration-1',
            proposal: { kind: 'meal' },
            status: 'cancelled',
            created_at: '2026-07-20T12:00:00Z',
            expires_at: '2026-07-21T12:00:00Z',
            resolved_at: '2026-07-20T12:10:00Z',
          },
          error: null,
        }
      },
    }
    const supabase = { from: () => builder }

    await cancelRegistration(supabase as never, 'patient-1', 'registration-1')

    expect(filters).toEqual([
      ['id', 'registration-1'],
      ['user_id', 'patient-1'],
    ])
  })

  it('replays an already confirmed registration without writing it again', async () => {
    const builder = {
      select() {
        return this
      },
      eq() {
        return this
      },
      async maybeSingle() {
        return {
          data: {
            id: 'registration-1',
            proposal: { kind: 'meal', mealType: 'jantar' },
            status: 'confirmed',
            created_at: '2026-07-20T12:00:00Z',
            expires_at: '2026-07-21T12:00:00Z',
            resolved_at: '2026-07-20T12:10:00Z',
          },
          error: null,
        }
      },
    }
    const supabase = { from: () => builder }

    await expect(
      confirmRegistration(
        supabase as never,
        { userId: 'patient-1', patient: {} } as never,
        'registration-1',
      ),
    ).resolves.toMatchObject({
      id: 'registration-1',
      status: 'confirmed',
      already_confirmed: true,
    })
  })
})

describe('mobile confirm — unresolved items (device gate 2026-09-27)', () => {
  function supabaseWithPending(items: unknown[]) {
    const writes: string[] = []
    const builder = {
      select() {
        return this
      },
      eq() {
        return this
      },
      update() {
        writes.push('update')
        return this
      },
      insert() {
        writes.push('insert')
        return this
      },
      async maybeSingle() {
        return {
          data: {
            id: 'registration-1',
            proposal: {
              kind: 'meal',
              mealType: 'jantar',
              items,
              source_provider_message_id: 'key-12345678',
              source_timestamp: '2026-09-28T00:49:47.884Z',
              source_timezone: 'America/Sao_Paulo',
              source_local_date: '2026-09-27',
            },
            status: 'pending',
            created_at: '2026-09-28T00:50:19Z',
            expires_at: '2999-01-01T00:00:00Z',
            resolved_at: null,
          },
          error: null,
        }
      },
    }
    return {
      writes,
      client: {
        from: () => builder,
        rpc: async (fn: string) => {
          writes.push(`rpc:${fn}`)
          return { data: null, error: null }
        },
      },
    }
  }

  it('refuses to confirm a proposal with an item the server has not calculated', async () => {
    const { client, writes } = supabaseWithPending([
      {
        name: 'Feijão carioca',
        nutrition_source: 'no_match',
        quantity_g: 86.5,
        kcal: 0,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 0,
        preparation_options: ['cru', 'cozido'],
      },
      {
        name: 'Frango grelhado',
        nutrition_source: 'canonical_exact',
        food_db_id: 7,
        quantity_g: 120,
        kcal: 191,
        protein_g: 38.44,
        carbs_g: 0,
        fat_g: 2.98,
      },
    ])

    await expect(
      confirmRegistration(
        client as never,
        { userId: 'patient-1', patient: { country: 'BR', timezone: 'America/Sao_Paulo' } } as never,
        'registration-1',
      ),
    ).rejects.toMatchObject({ status: 422, code: 'registration_unresolved_items' })
    expect(writes).toEqual([])
  })

  it('exposes the resolution and the preparation options of each pending item', () => {
    const proposal = buildMealPendingProposal(
      {
        kind: 'meal',
        meal_type: 'jantar',
        items: [
          { food_name: 'Feijão carioca', quantity_g: 86.5 },
          { food_name: 'Água', quantity_g: 250 },
        ],
      },
      {
        items: [
          {
            food_name: 'Feijão carioca',
            matched_taco_name: '',
            matched_taco_id: null,
            quantity_g: 86.5,
            kcal: 0,
            protein_g: 0,
            carbs_g: 0,
            fat_g: 0,
            fiber_g: 0,
            similarity: 0,
            source: 'no_match',
            preparation_options: ['cru', 'cozido'],
          },
          {
            food_name: 'Água',
            matched_taco_name: '[bebida zero]',
            matched_taco_id: null,
            quantity_g: 250,
            kcal: 0,
            protein_g: 0,
            carbs_g: 0,
            fat_g: 0,
            fiber_g: 0,
            similarity: 1,
            source: 'rule_based',
          },
        ],
        totals: { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 },
        warnings: [],
        user_warnings: ['Não sei se "Feijão carioca" era cru ou cozido'],
        audit_warnings: [],
      } as MealCalcResult,
      {
        requestKey: 'key-12345678',
        timestamp: '2026-09-28T00:49:47.884Z',
        timezone: 'America/Sao_Paulo',
        localDate: '2026-09-27',
      },
    )
    const dto = sanitizePendingProposal(proposal as never) as {
      items: Array<Record<string, unknown>>
    }
    expect(dto.items[0]).toMatchObject({
      name: 'Feijão carioca',
      kcal: 0,
      resolution: 'needs_clarification',
      preparation_options: ['cru', 'cozido'],
    })
    // A legitimate zero is resolved.
    expect(dto.items[1]).toMatchObject({
      name: 'Água',
      kcal: 0,
      resolution: 'resolved',
      preparation_options: null,
    })
  })
})
