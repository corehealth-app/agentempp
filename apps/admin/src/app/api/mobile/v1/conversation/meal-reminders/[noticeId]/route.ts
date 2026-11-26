import { z } from 'zod'
import { MobileApiError, mobileSuccess } from '@/lib/mobile-api/http'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

const noticeSchema = z.object({
  id: z.string().uuid(),
  local_date: z.string().date(),
  meal_type: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia']),
  state: z.enum(['pending', 'resolved', 'expired', 'processing']),
})

interface NoticeRouteContext {
  params: Promise<{ noticeId: string }>
}

export const GET = createMobileRouteWithContext<NoticeRouteContext>(async (context, route) => {
  if (
    process.env.MOBILE_FLOW_MEAL_GAP_PUSH_ENABLED !== 'true' ||
    process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/u, '') !==
      'https://xitugspwfxkcluxvrdeg.supabase.co'
  ) {
    throw new MobileApiError(
      503,
      'flow_meal_gap_unavailable',
      'Flow meal reminders are unavailable',
    )
  }
  const noticeId = noticeSchema.shape.id.parse((await route.params).noticeId)
  const { data, error } = await (
    context.supabase as unknown as {
      rpc(
        name: 'read_flow_meal_gap_notice',
        params: { p_user_id: string; p_notice_id: string },
      ): Promise<{ data: unknown; error: unknown }>
    }
  ).rpc('read_flow_meal_gap_notice', {
    p_user_id: context.auth.userId,
    p_notice_id: noticeId,
  })
  if (error)
    throw new MobileApiError(500, 'data_access_failed', 'Unable to read Flow meal reminder')
  if (data === null)
    throw new MobileApiError(404, 'flow_meal_gap_not_found', 'Flow meal reminder was not found')
  const notice = noticeSchema.safeParse(data)
  if (!notice.success || notice.data.id !== noticeId)
    throw new MobileApiError(500, 'data_access_failed', 'Unable to read Flow meal reminder')
  return mobileSuccess(notice.data, context.requestId)
})
