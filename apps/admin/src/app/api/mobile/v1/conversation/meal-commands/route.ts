import { createConversationMealCommandRoutes } from '@/lib/mobile-api/conversation-meal-command-routes'

export const runtime = 'nodejs'
export const maxDuration = 120

export const POST = createConversationMealCommandRoutes().POST
