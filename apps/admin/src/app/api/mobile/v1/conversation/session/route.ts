import { createConversationMealCommandRoutes } from '@/lib/mobile-api/conversation-meal-command-routes'
import { createConversationSessionInitializationRoute } from '@/lib/mobile-api/conversation-session-initialization-route'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export const GET = createConversationMealCommandRoutes().SESSION
export const POST = createConversationSessionInitializationRoute()
