import { createWorkoutStrengthClarificationRoutes } from '@/lib/mobile-api/workout-strength-clarification-route-handlers'

export const runtime = 'nodejs'
const routes = createWorkoutStrengthClarificationRoutes()
export const GET = routes.GET
export const POST = routes.POST
