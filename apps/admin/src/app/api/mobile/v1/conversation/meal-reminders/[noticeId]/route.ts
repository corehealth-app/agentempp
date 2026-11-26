import { z } from 'zod'
import { MobileApiError, mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { createMobileRouteWithContext, type MobileRouteContext } from '@/lib/mobile-api/route'

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

const skipInput = z.object({ action: z.literal('skipped') }).strict()

async function reminder(context: MobileRouteContext, route: NoticeRouteContext, skip: boolean) {
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
  if (skip) skipInput.parse(await readJsonBody(context.request))
  const { data, error } = await (
    context.supabase as unknown as {
      rpc(
        name: 'read_flow_meal_gap_notice' | 'skip_flow_meal_gap_notice',
        params: { p_user_id: string; p_notice_id: string },
      ): Promise<{ data: unknown; error: { code: string } | null }>
    }
  ).rpc(skip ? 'skip_flow_meal_gap_notice' : 'read_flow_meal_gap_notice', {
    p_user_id: context.auth.userId,
    p_notice_id: noticeId,
  })
  if (error?.code === '55P03')
    throw new MobileApiError(409, 'flow_meal_gap_day_busy', 'The diary is updating')
  if (error)
    throw new MobileApiError(500, 'data_access_failed', 'Unable to read Flow meal reminder')
  if (data === null)
    throw new MobileApiError(404, 'flow_meal_gap_not_found', 'Flow meal reminder was not found')
  const notice = noticeSchema.safeParse(data)
  if (!notice.success || notice.data.id !== noticeId)
    throw new MobileApiError(500, 'data_access_failed', 'Unable to read Flow meal reminder')
  return mobileSuccess(notice.data, context.requestId)
}

export const GET = createMobileRouteWithContext<NoticeRouteContext>((context, route) =>
  reminder(context, route, false),
)
export const POST = createMobileRouteWithContext<NoticeRouteContext>((context, route) =>
  reminder(context, route, true),
)
