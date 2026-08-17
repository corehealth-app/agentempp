import { describe, expect, it, vi } from 'vitest'
import { aggregateFoodDbGaps, collectPages } from './food-db-gaps.js'

describe('aggregateFoodDbGaps', () => {
  it('excludes canonical foods regardless of accents, casing, and surrounding spaces', () => {
    const result = aggregateFoodDbGaps(
      [
        { food_name: ' Café com leite ', kcal: 80, quantity_g: 200, user_id: 'u1' },
        { food_name: 'CAFE COM LEITE', kcal: 90, quantity_g: 220, user_id: 'u2' },
      ],
      ['cafe com leite'],
    )

    expect(result.gaps).toEqual([])
    expect(result.summary).toEqual({ total_logs: 2, fallback_logs: 0, fallback_pct: 0 })
  })

  it('aggregates only unknown foods and orders by logs then patients', () => {
    const result = aggregateFoodDbGaps(
      [
        { food_name: 'item raro', kcal: 100, quantity_g: 50, user_id: 'u1' },
        { food_name: 'item raro', kcal: 120, quantity_g: 60, user_id: 'u2' },
        { food_name: 'outro item', kcal: 90, quantity_g: 100, user_id: 'u1' },
        { food_name: 'arroz branco', kcal: 128, quantity_g: 100, user_id: 'u1' },
      ],
      ['arroz branco'],
    )

    expect(result.gaps).toEqual([
      {
        food_name: 'item raro',
        logs: 2,
        patients: 2,
        avg_kcal_per_100g: 200,
      },
      {
        food_name: 'outro item',
        logs: 1,
        patients: 1,
        avg_kcal_per_100g: 90,
      },
    ])
    expect(result.summary).toEqual({ total_logs: 4, fallback_logs: 3, fallback_pct: 75 })
  })

  it('ignores invalid quantities when calculating the average', () => {
    const result = aggregateFoodDbGaps(
      [
        { food_name: 'produto novo', kcal: 100, quantity_g: 0, user_id: 'u1' },
        { food_name: 'produto novo', kcal: null, quantity_g: 50, user_id: 'u1' },
      ],
      [],
    )

    expect(result.gaps[0]?.avg_kcal_per_100g).toBe(0)
  })
})

describe('collectPages', () => {
  it('loads every page until the first partial page', async () => {
    const loadPage = vi
      .fn<(from: number, to: number) => Promise<number[]>>()
      .mockResolvedValueOnce([1, 2])
      .mockResolvedValueOnce([3, 4])
      .mockResolvedValueOnce([5])

    await expect(collectPages(loadPage, 2)).resolves.toEqual([1, 2, 3, 4, 5])
    expect(loadPage.mock.calls).toEqual([
      [0, 1],
      [2, 3],
      [4, 5],
    ])
  })
})
