import { createMobileRoute } from '@/lib/mobile-api/route'
import { handleProtocolGet } from './handler'

export const runtime = 'nodejs'

export const GET = createMobileRoute(handleProtocolGet)
