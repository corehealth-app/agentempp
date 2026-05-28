import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { WhatsAppCloudProvider } from './whatsapp-cloud.js'

// Trava o fix do botão WhatsApp (Roberto 2026-05-28, Fase A botões #4):
// sendInteractive valida limites Meta (max 3 botões, title ≤20 chars,
// body ≤1024 chars, id ≤256 chars) ANTES de mandar — falha rápido em vez
// de a Meta rejeitar silencioso.

const cfg = {
  phoneNumberId: 'PNID',
  accessToken: 'TOKEN',
  appSecret: 'SECRET',
  verifyToken: 'VTOKEN',
}

describe('WhatsAppCloudProvider.sendInteractive — validação de limites Meta', () => {
  let provider: WhatsAppCloudProvider
  beforeEach(() => {
    provider = new WhatsAppCloudProvider(cfg)
    // Mocka fetch pra não bater na Meta de verdade durante teste de validação
    vi.stubGlobal(
      'fetch',
      vi.fn(async () =>
        new Response(JSON.stringify({ messages: [{ id: 'wamid.MOCK' }] }), { status: 200 }),
      ),
    )
  })
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('REJEITA quando buttons vazio', async () => {
    await expect(provider.sendInteractive('5511999999999', 'oi', [])).rejects.toThrow(/buttons.length/)
  })

  it('REJEITA quando buttons > 3', async () => {
    const buttons = Array.from({ length: 4 }, (_, i) => ({ id: `b${i}`, title: `T${i}` }))
    await expect(provider.sendInteractive('5511999999999', 'oi', buttons)).rejects.toThrow(/buttons.length/)
  })

  it('REJEITA body vazio ou > 1024 chars', async () => {
    await expect(provider.sendInteractive('5511999999999', '', [{ id: 'a', title: 'A' }])).rejects.toThrow(/body length/)
    const huge = 'x'.repeat(1025)
    await expect(provider.sendInteractive('5511999999999', huge, [{ id: 'a', title: 'A' }])).rejects.toThrow(/body length/)
  })

  it('REJEITA title > 20 chars (limite Meta)', async () => {
    await expect(
      provider.sendInteractive('5511999999999', 'oi', [
        { id: 'a', title: 'Esse título tem mais de vinte chars' },
      ]),
    ).rejects.toThrow(/title length/)
  })

  it('REJEITA id > 256 chars', async () => {
    await expect(
      provider.sendInteractive('5511999999999', 'oi', [{ id: 'x'.repeat(300), title: 'A' }]),
    ).rejects.toThrow(/id length/)
  })

  it('ACEITA caso válido (2 botões, body ok, title ≤20)', async () => {
    const r = await provider.sendInteractive('5511999999999', 'Confirma?', [
      { id: 'confirm_abc', title: 'Sim, registrar' }, // 15 chars
      { id: 'edit_abc', title: 'Editar' }, // 6 chars
    ])
    expect(r.status).toBe('sent')
    expect(r.providerMessageId).toBe('wamid.MOCK')
  })

  it('envia o payload no formato correto da Meta (type=interactive, button reply)', async () => {
    const fetchMock = global.fetch as ReturnType<typeof vi.fn>
    await provider.sendInteractive('5511999999999', 'Confirma?', [
      { id: 'confirm_abc', title: 'Sim, registrar' },
    ])
    const callArgs = fetchMock.mock.calls[0]!
    const body = JSON.parse(callArgs[1]!.body as string) as {
      type: string
      interactive: { type: string; body: { text: string }; action: { buttons: unknown[] } }
    }
    expect(body.type).toBe('interactive')
    expect(body.interactive.type).toBe('button')
    expect(body.interactive.body.text).toBe('Confirma?')
    expect(body.interactive.action.buttons[0]).toEqual({
      type: 'reply',
      reply: { id: 'confirm_abc', title: 'Sim, registrar' },
    })
  })
})
