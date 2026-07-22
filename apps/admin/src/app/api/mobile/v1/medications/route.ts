import {
  createRoutineCollectionGetRoute,
  createRoutineCollectionPostRoute,
} from '@/lib/mobile-api/routine-route-handlers'

export const runtime = 'nodejs'

export const GET = createRoutineCollectionGetRoute('medication')
export const POST = createRoutineCollectionPostRoute('medication')
