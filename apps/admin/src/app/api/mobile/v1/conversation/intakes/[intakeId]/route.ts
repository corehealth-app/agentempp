import { createConversationIntakeRoutes } from '@/lib/mobile-api/conversation-intake-routes'

export const runtime = 'nodejs'
export const maxDuration = 120

export const GET = createConversationIntakeRoutes().GET
