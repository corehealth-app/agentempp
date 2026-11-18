import { createJourneySocialRoutes } from '@/lib/mobile-api/journey-social-routes'
export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const GET = createJourneySocialRoutes().BLOCKS_GET
export const POST = createJourneySocialRoutes().BLOCKS_POST
