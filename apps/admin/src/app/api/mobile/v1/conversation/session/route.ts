import { createConversationMealCommandRoutes } from '@/lib/mobile-api/conversation-meal-command-routes'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export const GET = createConversationMealCommandRoutes().SESSION
