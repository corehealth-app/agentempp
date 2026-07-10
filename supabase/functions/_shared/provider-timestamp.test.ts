import { assertEquals } from 'jsr:@std/assert@1'
import { resolveProviderTimestamp } from './provider-timestamp.ts'

Deno.test('usa o timestamp do WhatsApp quando ele e valido', () => {
  const result = resolveProviderTimestamp('1783653585', new Date('2026-07-10T03:19:49.000Z'))

  assertEquals(result, {
    timestamp: '2026-07-10T03:19:45.000Z',
    serverReceivedAt: '2026-07-10T03:19:49.000Z',
    source: 'provider',
    fallbackReason: null,
  })
})

Deno.test('faz fallback para o servidor quando o timestamp esta no futuro', () => {
  const result = resolveProviderTimestamp('1783654000', new Date('2026-07-10T03:19:49.000Z'))

  assertEquals(result.timestamp, '2026-07-10T03:19:49.000Z')
  assertEquals(result.source, 'server_fallback')
  assertEquals(result.fallbackReason, 'future_timestamp')
})

Deno.test('faz fallback para o servidor quando o timestamp e invalido', () => {
  const result = resolveProviderTimestamp('nao-e-epoch', new Date('2026-07-10T03:19:49.000Z'))

  assertEquals(result.timestamp, '2026-07-10T03:19:49.000Z')
  assertEquals(result.source, 'server_fallback')
  assertEquals(result.fallbackReason, 'invalid_timestamp')
})
