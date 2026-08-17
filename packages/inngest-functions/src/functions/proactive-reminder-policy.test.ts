import { describe, expect, it } from 'vitest'
import { isProactiveReminderHour } from './proactive-reminder-policy.js'

describe('isProactiveReminderHour', () => {
  it.each([10, 11, 18, 19])('aceita %ih no fuso local do paciente', (hour) => {
    expect(isProactiveReminderHour(hour)).toBe(true)
  })

  it.each([0, 9, 20, 23])('rejeita %ih fora da janela local', (hour) => {
    expect(isProactiveReminderHour(hour)).toBe(false)
  })
})
