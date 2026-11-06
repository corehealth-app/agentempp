import { createConversationMealQuestionReadRoutes } from '@/lib/mobile-api/conversation-meal-question-read-routes'
import { createConversationMealReplyPublicRoutes } from '@/lib/mobile-api/conversation-meal-reply-public-routes'

export const runtime = 'nodejs'
export const maxDuration = 120

export const POST = createConversationMealReplyPublicRoutes().POST
export const GET = createConversationMealQuestionReadRoutes().GET
