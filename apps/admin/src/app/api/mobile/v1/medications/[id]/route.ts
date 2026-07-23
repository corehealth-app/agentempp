import {
  createRoutineItemArchiveRoute,
  createRoutineItemPatchRoute,
} from '@/lib/mobile-api/routine-route-handlers'

export const runtime = 'nodejs'

export const PATCH = createRoutineItemPatchRoute('medication')
export const DELETE = createRoutineItemArchiveRoute('medication')
