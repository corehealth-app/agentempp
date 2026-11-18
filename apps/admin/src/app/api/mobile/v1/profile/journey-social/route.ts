import { createJourneySocialRoutes } from '@/lib/mobile-api/journey-social-routes'
export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const GET = createJourneySocialRoutes().PROFILE_GET
export const PATCH = createJourneySocialRoutes().PROFILE_PATCH
