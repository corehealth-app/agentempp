import { createRevenueCatWebhookHandler } from '@/lib/billing/revenuecat-webhook-handler'

export const runtime = 'nodejs'

export const POST = createRevenueCatWebhookHandler()
