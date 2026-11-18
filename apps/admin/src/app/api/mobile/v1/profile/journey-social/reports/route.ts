import { createJourneySocialRoutes } from '@/lib/mobile-api/journey-social-routes'
export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const POST = createJourneySocialRoutes().REPORTS_POST
