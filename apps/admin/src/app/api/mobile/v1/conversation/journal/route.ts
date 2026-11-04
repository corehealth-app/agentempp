import { createConversationMealJournalRoutes } from '@/lib/mobile-api/conversation-meal-journal-routes'

export const runtime = 'nodejs'

export const GET = createConversationMealJournalRoutes().GET
