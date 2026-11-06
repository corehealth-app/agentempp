import { createConversationIntakeRoutes } from '@/lib/mobile-api/conversation-intake-routes'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export const GET = createConversationIntakeRoutes().SESSION
