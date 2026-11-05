import { createNutritionWindowRoutes } from '@/lib/mobile-api/nutrition-window-routes'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const GET = createNutritionWindowRoutes().GET
