import { createTrainingExecutionRoutes } from '@/lib/mobile-api/training-execution-routes'
export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const GET = createTrainingExecutionRoutes().HOME
