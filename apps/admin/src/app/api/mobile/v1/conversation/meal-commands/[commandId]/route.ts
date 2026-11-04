import { createConversationMealCommandRoutes } from '@/lib/mobile-api/conversation-meal-command-routes'

export const runtime = 'nodejs'

export const GET = createConversationMealCommandRoutes().GET
