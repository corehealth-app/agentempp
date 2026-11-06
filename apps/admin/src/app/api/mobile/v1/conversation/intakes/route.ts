import { createConversationIntakeRoutes } from '@/lib/mobile-api/conversation-intake-routes'
import { createConversationMealQuestionOriginsRoutes } from '@/lib/mobile-api/conversation-meal-question-origins-routes'

export const runtime = 'nodejs'
export const maxDuration = 120

export const POST = createConversationIntakeRoutes().POST
export const GET = createConversationMealQuestionOriginsRoutes().GET
