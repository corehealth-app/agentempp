import { describe, expect, it } from 'vitest'
import { parseBooleanRuntimeValue } from './runtime-config.js'

describe('parseBooleanRuntimeValue', () => {
  it('aceita boolean, number e strings comuns', () => {
    expect(parseBooleanRuntimeValue(true, false)).toBe(true)
    expect(parseBooleanRuntimeValue(false, true)).toBe(false)
    expect(parseBooleanRuntimeValue(1, false)).toBe(true)
    expect(parseBooleanRuntimeValue(0, true)).toBe(false)
    expect(parseBooleanRuntimeValue('enabled', false)).toBe(true)
    expect(parseBooleanRuntimeValue('off', true)).toBe(false)
  })

  it('preserva fallback para valores ambíguos', () => {
    expect(parseBooleanRuntimeValue('talvez', false)).toBe(false)
    expect(parseBooleanRuntimeValue('talvez', true)).toBe(true)
    expect(parseBooleanRuntimeValue(null, true)).toBe(true)
  })
})
