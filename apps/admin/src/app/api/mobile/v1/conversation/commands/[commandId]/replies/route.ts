import { createConversationMealReplyPublicRoutes } from '@/lib/mobile-api/conversation-meal-reply-public-routes'

export const runtime = 'nodejs'
export const maxDuration = 120

export const POST = createConversationMealReplyPublicRoutes().POST
