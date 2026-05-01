import { allFunctions, inngest } from '@mpp/inngest-functions'
import { serve } from 'inngest/next'

/**
 * Endpoint que serve as Inngest functions.
 *
 * Em dev: Inngest Dev Server (npx inngest-cli@latest dev) descobre via
 * GET /api/inngest e roteia eventos para esse endpoint.
 *
 * Em prod: Inngest Cloud chama POST /api/inngest com payload assinado
 * (verificado via INNGEST_SIGNING_KEY no env).
 */
export const { GET, POST, PUT } = serve({
  client: inngest,
  functions: allFunctions,
  // streaming desativado para Edge Runtime do Vercel
  streaming: 'allow',
})

export const runtime = 'nodejs'
export const maxDuration = 300
