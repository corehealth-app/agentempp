import { describe, expect, it } from 'vitest'
import { parseConfirmedMealReceipt } from './confirmed-meal-mutation-service'

const id = 'c1110000-0000-4000-8000-000000000003'
const next = 'c1110000-0000-4000-8000-000000000004'
function receipt(operation: 'updated' | 'deleted' = 'updated') {
  return {
    data: {
      record_id: id,
      operation,
      removed_item_ids: [id],
      new_item_ids: operation === 'updated' ? [next] : [],
      next_record_id: operation === 'updated' ? next : null,
      snapshot: {
        id: 'c1110000-0000-4000-8000-000000000005',
        date: '2026-10-09',
        calories_consumed: 110,
        protein_g: 6,
        carbs_g: 9,
        fat_g: 5.5,
        daily_balance: -1790,
      },
    },
    meta: { api_version: 'v1', request_id: 'original-request' },
  }
}

describe('confirmed meal receipt validation', () => {
  it.each(['updated', 'deleted'] as const)('accepts the official %s receipt', (operation) => {
    const body = receipt(operation)
    expect(
      parseConfirmedMealReceipt(body, id, operation === 'updated' ? 'PATCH' : 'DELETE', [id]),
    ).toEqual(body.data)
  })
  it('keeps nullable persisted balance and a surviving group anchor in DELETE', () => {
    const body = {
      ...receipt('deleted'),
      data: {
        ...receipt('deleted').data,
        next_record_id: next,
        snapshot: { ...receipt('deleted').data.snapshot, daily_balance: null },
      },
    }
    expect(parseConfirmedMealReceipt(body, id, 'DELETE', [id])).toEqual(body.data)
  })
  it.each([
    { ...receipt(), data: { ...receipt().data, record_id: next } },
    { ...receipt(), data: { ...receipt().data, operation: 'deleted' } },
    { ...receipt(), data: { ...receipt().data, removed_item_ids: [next] } },
    { ...receipt(), data: { ...receipt().data, new_item_ids: [id] } },
    { ...receipt(), data: { ...receipt().data, new_item_ids: [next, next] } },
    { ...receipt(), data: { ...receipt().data, next_record_id: null } },
    { ...receipt(), data: { ...receipt().data, user_id: next } },
    {
      ...receipt(),
      data: { ...receipt().data, snapshot: { ...receipt().data.snapshot, private_context: {} } },
    },
    {
      ...receipt(),
      data: { ...receipt().data, snapshot: { ...receipt().data.snapshot, calories_consumed: -1 } },
    },
    {
      ...receipt(),
      data: { ...receipt().data, snapshot: { ...receipt().data.snapshot, protein_g: Infinity } },
    },
    { ...receipt(), meta: { api_version: 'v2', request_id: 'original-request' } },
  ])('rejects an untrusted/inconsistent PATCH receipt %# as unresolved result', (body) => {
    expect(() => parseConfirmedMealReceipt(body, id, 'PATCH', [id])).toThrowError(
      expect.objectContaining({ status: 503, code: 'MEAL_RECEIPT_INVALID' }),
    )
  })
  it('refuses DELETE that claims newly inserted foods', () => {
    expect(() => parseConfirmedMealReceipt(receipt(), id, 'DELETE', [id])).toThrowError(
      expect.objectContaining({ code: 'MEAL_RECEIPT_INVALID' }),
    )
  })
})
