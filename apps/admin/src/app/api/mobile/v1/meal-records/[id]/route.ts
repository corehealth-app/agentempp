import { createConfirmedMealRoutes } from '@/lib/mobile-api/confirmed-meal-route-handlers'

export const runtime = 'nodejs'

const routes = createConfirmedMealRoutes()
export const GET = routes.GET
export const PATCH = routes.PATCH
export const DELETE = routes.DELETE
