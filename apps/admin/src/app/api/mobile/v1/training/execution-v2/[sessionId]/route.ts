import { createTrainingExecutionCompletionRoutes } from '@/lib/mobile-api/training-execution-completion-routes'
export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const GET = createTrainingExecutionCompletionRoutes().STATE

export const POST = createTrainingExecutionCompletionRoutes().PROGRESS
