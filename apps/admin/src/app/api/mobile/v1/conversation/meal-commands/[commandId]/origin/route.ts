import { createConversationMealLinkedOriginRoutes } from '@/lib/mobile-api/conversation-meal-linked-origin-routes'

export const runtime = 'nodejs'
export const maxDuration = 120
export const GET = createConversationMealLinkedOriginRoutes().GET
