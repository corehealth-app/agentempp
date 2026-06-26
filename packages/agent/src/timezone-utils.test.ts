import { describe, it, expect } from 'vitest'
import { getLocalDateString, getTzOffset } from './timezone-utils.js'

describe('getLocalDateString', () => {
  it('retorna data UTC quando tz=UTC', () => {
    // 2026-05-07T23:30Z em UTC = 2026-05-07
    expect(getLocalDateString('UTC', new Date('2026-05-07T23:30:00Z'))).toBe('2026-05-07')
  })

  it('America/New_York: UTC já virou amanhã, mas local ainda é hoje (EDT, UTC-4)', () => {
    // 2026-05-08T03:30Z UTC = 2026-05-07T23:30 em EDT
    expect(getLocalDateString('America/New_York', new Date('2026-05-08T03:30:00Z'))).toBe(
      '2026-05-07',
    )
  })

  it('America/Sao_Paulo: UTC já virou amanhã, local ainda é hoje (BRT, UTC-3)', () => {
    // 2026-05-08T02:30Z UTC = 2026-05-07T23:30 em BRT
    expect(getLocalDateString('America/Sao_Paulo', new Date('2026-05-08T02:30:00Z'))).toBe(
      '2026-05-07',
    )
  })

  it('Asia/Tokyo: UTC ainda hoje, local já amanhã (UTC+9)', () => {
    // 2026-05-07T22:00Z UTC = 2026-05-08T07:00 em Tóquio
    expect(getLocalDateString('Asia/Tokyo', new Date('2026-05-07T22:00:00Z'))).toBe(
      '2026-05-08',
    )
  })

  it('formato YYYY-MM-DD compatível com SQL date', () => {
    const r = getLocalDateString('America/New_York', new Date('2026-01-05T15:00:00Z'))
    expect(r).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    expect(r).toBe('2026-01-05')
  })

  it('default sem when usa Date now', () => {
    const r = getLocalDateString('America/Sao_Paulo')
    expect(r).toMatch(/^\d{4}-\d{2}-\d{2}$/)
  })
})

// Audit 06-26 sprint pendentes: refactor de interactive-handler depende do
// formato canônico ±HH:MM pra .gte/.lt no PostgREST. Sem teste, regressão
// silenciosa quebraria buffer_append_msg + queries time-range.
describe('getTzOffset', () => {
  it('UTC → +00:00', () => {
    expect(getTzOffset('UTC')).toBe('+00:00')
  })

  it('America/Sao_Paulo (sem DST 2026) → -03:00', () => {
    // Brasil aboliu DST em 2019. Sempre UTC-3.
    expect(getTzOffset('America/Sao_Paulo', new Date('2026-01-15T12:00:00Z'))).toBe('-03:00')
    expect(getTzOffset('America/Sao_Paulo', new Date('2026-07-15T12:00:00Z'))).toBe('-03:00')
  })

  it('DST-aware America/New_York: EST (jan) -05:00, EDT (jul) -04:00', () => {
    expect(getTzOffset('America/New_York', new Date('2026-01-15T12:00:00Z'))).toBe('-05:00')
    expect(getTzOffset('America/New_York', new Date('2026-07-15T12:00:00Z'))).toBe('-04:00')
  })

  it('Asia/Tokyo → +09:00 (sem DST)', () => {
    expect(getTzOffset('Asia/Tokyo', new Date('2026-01-15T12:00:00Z'))).toBe('+09:00')
  })

  it('Asia/Kolkata → +05:30 (offset com minutos)', () => {
    expect(getTzOffset('Asia/Kolkata', new Date('2026-06-15T12:00:00Z'))).toBe('+05:30')
  })

  it('formato canônico ±HH:MM compatível com PostgREST', () => {
    const tzs = ['UTC', 'America/Sao_Paulo', 'America/New_York', 'Asia/Tokyo', 'Asia/Kolkata']
    for (const tz of tzs) {
      const off = getTzOffset(tz)
      expect(off).toMatch(/^[+-]\d{2}:\d{2}$/)
    }
  })
})
