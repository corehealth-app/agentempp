import { createConversationWorkoutCommandRoutes } from '@/lib/mobile-api/conversation-workout-command-routes'

export const runtime = 'nodejs'
export const maxDuration = 120

export const GET = createConversationWorkoutCommandRoutes().GET
