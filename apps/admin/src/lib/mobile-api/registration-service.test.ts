import type { MealCalcResult } from '@mpp/agent'
import { describe, expect, it } from 'vitest'
import {
  buildMealPendingProposal,
  cancelRegistration,
  proposeRegistration,
} from './registration-service'

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
})
