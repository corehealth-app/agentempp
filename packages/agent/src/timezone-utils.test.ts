import { describe, it, expect } from 'vitest'
import { getLocalDateString } from './timezone-utils.js'

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
