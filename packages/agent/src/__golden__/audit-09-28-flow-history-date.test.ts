/**
 * Golden test — Flow (mobile) answer grounded on the previous day, staging
 * device gate of 2026-09-28 (QA account A, America/Sao_Paulo).
 *
 * Exact scenario: on 27/09 at 23:43 local the patient asked
 * "Quanto eu ja comi hoje?" and Flow answered with that day's numbers
 * ("Hoje você tá em 676 kcal de 3.355 …" / "São 23h …"). On 28/09 at 21:08
 * local, with no meal on 28/09 (no daily snapshot; the context said
 * "Consumo hoje: 0 kcal"), the patient asked "Qual é a minha meta de hoje e
 * quanto falta?" and Flow repeated "Você já consumiu 676 kcal e 59,6 g".
 * The history rows reached the model with no date, so yesterday's "hoje"
 * read as today's.
 *
 * Message contents below are the exact leading text stored in staging
 * `messages` (provider mobile_flow); the tail of the answer is omitted.
 * WhatsApp history is not changed: without the date option the rows pass
 * through exactly as before.
 */
import { describe, expect, it } from 'vitest'
import { buildPromptRecentMessages } from '../pipeline.js'

const yesterdayAnswer =
  'Hoje você tá em 676 kcal de 3.355 — ainda bem abaixo da meta.\n\nProteína: 59,6 g de 185,4 g. Falta bastante ainda.\n\nSão 23h, então o dia tá quase fechando.'

// Newest first, as the history query returns them.
const rows = [
  {
    direction: 'in',
    content: 'Qual é a minha meta de hoje e quanto falta?',
    created_at: '2026-09-29T00:08:34.286Z',
    provider_message_id: 'flow-current',
  },
  { direction: 'out', content: yesterdayAnswer, created_at: '2026-09-28T02:43:53.130Z' },
  { direction: 'in', content: 'Quanto eu ja comi hoje?', created_at: '2026-09-28T02:43:41.662Z' },
]

describe('audit 2026-09-28 — Flow history from a previous local day', () => {
  const today = { timeZone: 'America/Sao_Paulo', today: '2026-09-28' }

  it('marks each message of 27/09 as a previous day whose numbers and time do not hold today', () => {
    const history = buildPromptRecentMessages(rows, 'flow-current', today)
    expect(history).toHaveLength(2)
    for (const message of history) {
      expect(message.content.startsWith('[Mensagem de 27/09/2026, dia anterior')).toBe(true)
      expect(message.content).toContain('não valem para hoje')
    }
    expect(history[0]).toMatchObject({ role: 'user' })
    expect(history[0]!.content.endsWith('Quanto eu ja comi hoje?')).toBe(true)
    expect(history[1]).toMatchObject({ role: 'assistant' })
    expect(history[1]!.content.endsWith(yesterdayAnswer)).toBe(true)
  })

  it('uses the patient local day, not UTC: 02:43Z on 28/09 is still 27/09 in São Paulo', () => {
    const sameUtcDay = { timeZone: 'UTC', today: '2026-09-28' }
    const history = buildPromptRecentMessages(rows, 'flow-current', sameUtcDay)
    expect(history.map((m) => m.content)).toEqual(['Quanto eu ja comi hoje?', yesterdayAnswer])
  })

  it('leaves messages of the same local day untouched', () => {
    const laterToday = [
      { direction: 'out', content: 'Sua meta de hoje é 3.361 kcal.', created_at: '2026-09-29T00:08:44.406Z' },
      { direction: 'in', content: 'Qual é a minha meta?', created_at: '2026-09-29T00:08:34.286Z' },
    ]
    expect(buildPromptRecentMessages(laterToday, null, today)).toEqual([
      { role: 'user', content: 'Qual é a minha meta?' },
      { role: 'assistant', content: 'Sua meta de hoje é 3.361 kcal.' },
    ])
  })

  it('WhatsApp history (no date option) is unchanged', () => {
    expect(buildPromptRecentMessages(rows, 'flow-current')).toEqual([
      { role: 'user', content: 'Quanto eu ja comi hoje?' },
      { role: 'assistant', content: yesterdayAnswer },
    ])
  })

  it('a row from a later local day (concurrent turn across midnight) is not called a previous day', () => {
    const concurrent = [{ direction: 'in', content: 'Oi', created_at: '2026-09-29T03:00:01.000Z' }]
    expect(buildPromptRecentMessages(concurrent, null, today)).toEqual([{ role: 'user', content: 'Oi' }])
  })

  it('a row without a readable date is left untouched rather than guessed', () => {
    const undated = [{ direction: 'in', content: 'Oi', created_at: null }]
    expect(buildPromptRecentMessages(undated, null, today)).toEqual([{ role: 'user', content: 'Oi' }])
  })
})
