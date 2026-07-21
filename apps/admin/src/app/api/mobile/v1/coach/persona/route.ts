import { createMobileRoute } from '@/lib/mobile-api/route'
import { handleCoachPersonaGet, handleCoachPersonaPatch } from './handler'

export const runtime = 'nodejs'

export const GET = createMobileRoute((context) => handleCoachPersonaGet(context))

export const PATCH = createMobileRoute((context) => handleCoachPersonaPatch(context))
