import {
  createRoutineCollectionGetRoute,
  createRoutineCollectionPostRoute,
} from '@/lib/mobile-api/routine-route-handlers'

export const runtime = 'nodejs'

export const GET = createRoutineCollectionGetRoute('supplement')
export const POST = createRoutineCollectionPostRoute('supplement')
