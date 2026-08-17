export type TelegramApprovalAction = 'approve' | 'reject'

export type TelegramApplyResult =
  | ({ ok: true } & Record<string, unknown>)
  | { ok: false; reason: string }

export interface TelegramApprovalOutcome {
  status: 'rejected' | 'applied' | 'failed_to_apply'
  applicationResult: Record<string, unknown> | null
  applicationError: string | null
}

export function resolveTelegramApprovalOutcome(
  action: TelegramApprovalAction,
  result: TelegramApplyResult | null,
): TelegramApprovalOutcome {
  if (action === 'reject') {
    return { status: 'rejected', applicationResult: null, applicationError: null }
  }
  if (result?.ok) {
    return { status: 'applied', applicationResult: result, applicationError: null }
  }
  return {
    status: 'failed_to_apply',
    applicationResult: null,
    applicationError: result?.reason ?? 'application returned no result',
  }
}
