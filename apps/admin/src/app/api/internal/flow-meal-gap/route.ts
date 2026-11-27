import { claimFlowMealGapCron, runFlowMealGapPush } from '@mpp/inngest-functions/flow-meal-gap-push'

export const runtime = 'nodejs'
export const maxDuration = 300

export async function POST(request: Request) {
  const host = process.env.VERCEL_URL
  const target = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  if (
    process.env.INNGEST_FUNCTION_SET !== 'media-conversation-staging' ||
    process.env.MOBILE_FLOW_MEAL_GAP_PUSH_ENABLED !== 'true' ||
    process.env.MOBILE_FLOW_MEAL_GAP_TRANSPORT !== 'supabase-cron' ||
    !host ||
    !/^agentempp-media-worker-staging-[a-z0-9]+-gestao-9664s-projects\.vercel\.app$/.test(host) ||
    ![
      'https://xitugspwfxkcluxvrdeg.supabase.co',
      'https://xitugspwfxkcluxvrdeg.supabase.co/',
    ].includes(target ?? '')
  ) {
    return new Response(null, { status: 404 })
  }

  const token = request.headers.get('x-performe-meal-gap-token')
  if (!token || !/^[0-9a-f]{64}$/.test(token)) return new Response(null, { status: 401 })

  try {
    if (!(await claimFlowMealGapCron(host, token))) return new Response(null, { status: 401 })
    return Response.json(await runFlowMealGapPush())
  } catch {
    return new Response(null, { status: 503 })
  }
}
