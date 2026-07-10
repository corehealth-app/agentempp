import { describe, expect, it } from 'vitest'
import {
  buildPendingTiming,
  burstCrossesLocalDate,
  resolveRegistrationTime,
} from './registration-time.js'

describe('resolveRegistrationTime', () => {
  it('mantem 23:19 de Orlando no dia local anterior ao UTC', () => {
    const result = resolveRegistrationTime({
      timezone: 'America/New_York',
      referenceTimestamp: new Date('2026-07-10T03:19:45.000Z'),
    })

    expect(result.localDate).toBe('2026-07-09')
    expect(result.occurredAtIso).toBe('2026-07-10T03:19:45.000Z')
    expect(result.source).toBe('reference_timestamp')
  })

  it('usa meio-dia local quando a data foi informada explicitamente', () => {
    const result = resolveRegistrationTime({
      timezone: 'America/New_York',
      referenceTimestamp: new Date('2026-07-10T03:19:45.000Z'),
      explicitDate: '2026-07-08',
    })

    expect(result.localDate).toBe('2026-07-08')
    expect(result.occurredAtIso).toBe('2026-07-08T12:00:00-04:00')
    expect(result.source).toBe('explicit_date')
  })
})

describe('pending timing', () => {
  it('preserva a data de origem quando a confirmacao ocorrer depois da meia-noite', () => {
    expect(
      buildPendingTiming('America/New_York', new Date('2026-07-10T03:59:50.000Z')),
    ).toEqual({
      source_timestamp: '2026-07-10T03:59:50.000Z',
      source_timezone: 'America/New_York',
      source_local_date: '2026-07-09',
    })
  })
})

describe('burstCrossesLocalDate', () => {
  it('detecta burst dos dois lados da meia-noite local', () => {
    expect(
      burstCrossesLocalDate('America/New_York', [
        new Date('2026-07-10T03:59:58.000Z'),
        new Date('2026-07-10T04:00:02.000Z'),
      ]),
    ).toBe(true)
  })

  it('nao sinaliza mensagens do mesmo dia local', () => {
    expect(
      burstCrossesLocalDate('America/New_York', [
        new Date('2026-07-10T03:59:40.000Z'),
        new Date('2026-07-10T03:59:58.000Z'),
      ]),
    ).toBe(false)
  })
})
