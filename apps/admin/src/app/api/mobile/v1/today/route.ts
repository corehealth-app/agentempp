import { createTodayGetRoute } from '@/lib/mobile-api/today-handler'

export const runtime = 'nodejs'

export const GET = createTodayGetRoute()
