import { assertEquals } from 'jsr:@std/assert@1'
import { resolveTelegramApprovalOutcome } from './telegram-approval.ts'

Deno.test('rejeição termina como rejected sem resultado de aplicação', () => {
  assertEquals(resolveTelegramApprovalOutcome('reject', null), {
    status: 'rejected',
    applicationResult: null,
    applicationError: null,
  })
})

Deno.test('aprovação aplicada termina como applied', () => {
  const result = { ok: true as const, food_db_id: 42 }
  assertEquals(resolveTelegramApprovalOutcome('approve', result), {
    status: 'applied',
    applicationResult: result,
    applicationError: null,
  })
})

Deno.test('falha de aplicação termina como failed_to_apply', () => {
  assertEquals(resolveTelegramApprovalOutcome('approve', { ok: false, reason: 'db failed' }), {
    status: 'failed_to_apply',
    applicationResult: null,
    applicationError: 'db failed',
  })
})
