import { describe, expect, it } from 'vitest'
import { buildPromptRecentMessages } from './pipeline.js'

describe('buildPromptRecentMessages', () => {
  it('remove a mensagem atual já persistida antes de anexar input.text ao prompt', () => {
    const rows = [
      {
        direction: 'in',
        content: '40 minutos de musculação',
        provider_message_id: 'wamid-current',
      },
      {
        direction: 'out',
        content: 'Jantar registrado',
        provider_message_id: 'wamid-out',
      },
      {
        direction: 'in',
        content: 'Jantar: pão com queijo',
        provider_message_id: 'wamid-prev',
      },
    ]

    expect(buildPromptRecentMessages(rows, 'wamid-current')).toEqual([
      { role: 'user', content: 'Jantar: pão com queijo' },
      { role: 'assistant', content: 'Jantar registrado' },
    ])
  })

  it('preserva o histórico quando o id atual não está na janela', () => {
    const rows = [
      { direction: 'out', content: 'Pronto.', provider_message_id: 'out-1' },
      { direction: 'in', content: 'Oi', provider_message_id: 'in-1' },
    ]

    expect(buildPromptRecentMessages(rows, 'new-message')).toEqual([
      { role: 'user', content: 'Oi' },
      { role: 'assistant', content: 'Pronto.' },
    ])
  })

  it('remove todas as mensagens atuais de um burst agregado', () => {
    const rows = [
      {
        direction: 'in',
        content: 'E 35 min de musculação',
        provider_message_id: 'wamid-current-2',
      },
      {
        direction: 'in',
        content: '20 min de bicicleta',
        provider_message_id: 'wamid-current-1',
      },
      {
        direction: 'out',
        content: 'Ontem fechado.',
        provider_message_id: 'wamid-out',
      },
    ]

    expect(
      buildPromptRecentMessages(rows, ['wamid-current-1', 'wamid-current-2']),
    ).toEqual([{ role: 'assistant', content: 'Ontem fechado.' }])
  })

  it('remove taps crus de botões interativos do histórico natural', () => {
    const rows = [
      {
        direction: 'in',
        content: 'confirm_988140ad-a99c-4c0d-84d1-992c8662bc07',
        content_type: 'interactive',
        provider_message_id: 'tap-1',
      },
      {
        direction: 'in',
        content: '40 minutos de musculação',
        content_type: 'text',
        provider_message_id: 'in-1',
      },
    ]

    expect(buildPromptRecentMessages(rows, 'new-message')).toEqual([
      { role: 'user', content: '40 minutos de musculação' },
    ])
  })
})
