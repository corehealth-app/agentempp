import { createJourneySocialRoutes } from '@/lib/mobile-api/journey-social-routes'
export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const GET = createJourneySocialRoutes().RANKING_GET
