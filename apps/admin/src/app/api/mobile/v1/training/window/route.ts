import { createTrainingWindowRoutes } from '@/lib/mobile-api/training-window-routes'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const GET = createTrainingWindowRoutes().GET
