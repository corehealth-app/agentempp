import { createConversationMealEditPublicRoutes } from '@/lib/mobile-api/conversation-meal-edit-public-routes'

export const runtime = 'nodejs'
export const maxDuration = 120
export const POST = createConversationMealEditPublicRoutes().EDIT
