/**
 * Tests — deriveMealState + classifyByPendingStatus.
 * Audit 06-26 Layer 2.2 prevention plan.
 */
import { describe, expect, it } from 'vitest'
import { classifyByPendingStatus, deriveMealState } from './derive.js'

describe('deriveMealState', () => {
  it('PROPOSED: pending status=pending sem meal_logs', () => {
    const r = deriveMealState({
      pending: { status: 'pending', resolved_at: null, created_at: '2026-06-26T10:00:00Z' },
      mealLogs: [],
    })
    expect(r.state).toBe('PROPOSED')
    expect(r.provenance).toBe('pending_only')
  })

  it('CONFIRMED: pending status=confirmed + meal_logs', () => {
    const r = deriveMealState({
      pending: {
        status: 'confirmed',
        resolved_at: '2026-06-26T10:01:00Z',
        created_at: '2026-06-26T10:00:00Z',
      },
      mealLogs: [
        { id: 'a', kcal: 500, food_name: 'arroz', created_at: '2026-06-26T10:01:05Z' },
      ],
    })
    expect(r.state).toBe('CONFIRMED')
    expect(r.provenance).toBe('pending+logs')
  })

  it('CONFIRMED drift: pending=confirmed mas SEM meal_log → PROPOSED (handler falhou)', () => {
    const r = deriveMealState({
      pending: {
        status: 'confirmed',
        resolved_at: '2026-06-26T10:01:00Z',
        created_at: '2026-06-26T10:00:00Z',
      },
      mealLogs: [],
    })
    expect(r.state).toBe('PROPOSED') // detecção de drift
  })

  it('CANCELLED: pending cancelled', () => {
    const r = deriveMealState({
      pending: {
        status: 'cancelled',
        resolved_at: '2026-06-26T10:01:00Z',
        created_at: '2026-06-26T10:00:00Z',
      },
      mealLogs: [],
    })
    expect(r.state).toBe('CANCELLED')
  })

  it('EDITED: pending edited', () => {
    const r = deriveMealState({
      pending: {
        status: 'edited',
        resolved_at: '2026-06-26T10:01:00Z',
        created_at: '2026-06-26T10:00:00Z',
      },
      mealLogs: [],
    })
    expect(r.state).toBe('EDITED')
  })

  it('EXPIRED: pending expired', () => {
    const r = deriveMealState({
      pending: {
        status: 'expired',
        resolved_at: '2026-06-27T10:00:00Z',
        created_at: '2026-06-26T10:00:00Z',
      },
      mealLogs: [],
    })
    expect(r.state).toBe('EXPIRED')
  })

  it('REGISTERED: express path (meal_logs sem pending)', () => {
    const r = deriveMealState({
      pending: null,
      mealLogs: [
        { id: 'a', kcal: 500, food_name: 'arroz', created_at: '2026-06-26T10:00:00Z' },
      ],
    })
    expect(r.state).toBe('REGISTERED')
    expect(r.provenance).toBe('express')
  })

  it('CORRECTED: meal_logs + hasReplaceAfter', () => {
    const r = deriveMealState({
      pending: null,
      mealLogs: [
        { id: 'a', kcal: 500, food_name: 'arroz', created_at: '2026-06-26T10:00:00Z' },
      ],
      hasReplaceAfter: true,
    })
    expect(r.state).toBe('CORRECTED')
    expect(r.provenance).toBe('replaced')
  })

  it('RECLASSIFIED: meal_logs + hasReclassifyAfter', () => {
    const r = deriveMealState({
      pending: null,
      mealLogs: [
        { id: 'a', kcal: 500, food_name: 'arroz', created_at: '2026-06-26T10:00:00Z' },
      ],
      hasReclassifyAfter: true,
    })
    expect(r.state).toBe('RECLASSIFIED')
    expect(r.provenance).toBe('reclassified')
  })

  it('SKIPPED: meal_log com kcal=0 e prefix "pulou_"', () => {
    const r = deriveMealState({
      pending: null,
      mealLogs: [
        {
          id: 'a',
          kcal: 0,
          food_name: 'pulou_jantar',
          created_at: '2026-06-26T10:00:00Z',
        },
      ],
    })
    expect(r.state).toBe('SKIPPED')
    expect(r.provenance).toBe('skip')
  })

  it('cenário Luciana 25/06: pending cancelled + meal_logs subset → CANCELLED (pending vence)', () => {
    const r = deriveMealState({
      pending: {
        status: 'cancelled',
        resolved_at: '2026-06-25T22:17:35Z',
        created_at: '2026-06-25T22:15:00Z',
      },
      mealLogs: [
        { id: 'fantasma1', kcal: 300, food_name: 'pão francês', created_at: '2026-06-25T22:17:35Z' },
        { id: 'fantasma2', kcal: 72, food_name: 'manteiga', created_at: '2026-06-25T22:17:35Z' },
      ],
    })
    expect(r.state).toBe('CANCELLED')
  })
})

describe('classifyByPendingStatus', () => {
  it('null + hasMealLogs → REGISTERED', () => {
    expect(classifyByPendingStatus(null, true, false)).toBe('REGISTERED')
  })

  it('null + sem meal_logs → PROPOSED', () => {
    expect(classifyByPendingStatus(null, false, false)).toBe('PROPOSED')
  })

  it('hasSkipSentinel sempre vence', () => {
    expect(classifyByPendingStatus('confirmed', true, true)).toBe('SKIPPED')
    expect(classifyByPendingStatus(null, true, true)).toBe('SKIPPED')
  })

  it('confirmed + hasMealLogs → CONFIRMED', () => {
    expect(classifyByPendingStatus('confirmed', true, false)).toBe('CONFIRMED')
  })

  it('confirmed sem meal_logs → PROPOSED (drift)', () => {
    expect(classifyByPendingStatus('confirmed', false, false)).toBe('PROPOSED')
  })

  it.each([
    ['pending', 'PROPOSED'],
    ['cancelled', 'CANCELLED'],
    ['edited', 'EDITED'],
    ['expired', 'EXPIRED'],
  ] as const)('status=%s → %s', (status, expected) => {
    expect(classifyByPendingStatus(status, false, false)).toBe(expected)
  })
})
