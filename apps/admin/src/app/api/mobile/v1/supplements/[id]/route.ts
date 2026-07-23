import {
  createRoutineItemArchiveRoute,
  createRoutineItemPatchRoute,
} from '@/lib/mobile-api/routine-route-handlers'

export const runtime = 'nodejs'

export const PATCH = createRoutineItemPatchRoute('supplement')
export const DELETE = createRoutineItemArchiveRoute('supplement')
