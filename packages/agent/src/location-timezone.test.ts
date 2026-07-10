import { describe, expect, it } from 'vitest'
import {
  findTimezoneCountryMismatches,
  isIanaTimezone,
  isMultiTimezoneCountry,
  resolveResidenceTimezone,
} from './location-timezone.js'

describe('location timezone validation', () => {
  it('reconhece America/New_York como IANA valido', () => {
    expect(isIanaTimezone('America/New_York')).toBe(true)
    expect(isIanaTimezone('Orlando/Florida')).toBe(false)
  })

  it('exige localizacao para nova confirmacao nos EUA sem timezone', () => {
    expect(
      resolveResidenceTimezone({
        country: 'US',
        requestedTimezone: null,
        existingCountry: null,
        existingTimezone: null,
        existingTimezoneConfirmed: false,
        locationProvided: true,
      }),
    ).toMatchObject({ ok: false, reason: 'location_required' })
  })

  it('preserva timezone ja confirmado ao trocar apenas idioma', () => {
    expect(
      resolveResidenceTimezone({
        country: 'US',
        requestedTimezone: null,
        existingCountry: 'US',
        existingTimezone: 'America/New_York',
        existingTimezoneConfirmed: true,
      }),
    ).toEqual({ ok: true, timezone: 'America/New_York', source: 'existing_confirmed' })
  })

  it('rejeita timezone brasileiro para residencia confirmada nos EUA', () => {
    expect(
      resolveResidenceTimezone({
        country: 'US',
        requestedTimezone: 'America/Sao_Paulo',
        existingCountry: null,
        existingTimezone: null,
        existingTimezoneConfirmed: false,
      }),
    ).toMatchObject({ ok: false, reason: 'country_timezone_mismatch' })
  })

  it('aceita Orlando como America/New_York', () => {
    expect(
      resolveResidenceTimezone({
        country: 'US',
        requestedTimezone: 'America/New_York',
        existingCountry: null,
        existingTimezone: null,
        existingTimezoneConfirmed: false,
        locationProvided: true,
      }),
    ).toEqual({ ok: true, timezone: 'America/New_York', source: 'explicit' })
  })

  it('marca US + Sao Paulo no auditor, sem marcar pais desconhecido', () => {
    expect(
      findTimezoneCountryMismatches([
        { id: 'u1', country: 'US', timezone: 'America/Sao_Paulo', country_confirmed: true },
        { id: 'u2', country: 'US', timezone: 'America/New_York', country_confirmed: true },
        { id: 'u3', country: 'ZZ', timezone: 'America/Sao_Paulo', country_confirmed: true },
      ]),
    ).toEqual([{ id: 'u1', country: 'US', timezone: 'America/Sao_Paulo' }])
  })

  it('classifica EUA e Brasil como paises de multiplos fusos', () => {
    expect(isMultiTimezoneCountry('US')).toBe(true)
    expect(isMultiTimezoneCountry('BR')).toBe(true)
    expect(isMultiTimezoneCountry('FR')).toBe(false)
  })
})
