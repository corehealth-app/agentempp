import { functionsForSet, inngest } from '@mpp/inngest-functions'
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
  // INNGEST_FUNCTION_SET unset: every function (production). 'media-staging':
  // only media processing, for the isolated staging worker.
  functions: [...functionsForSet(process.env.INNGEST_FUNCTION_SET)],
  // streaming desativado para Edge Runtime do Vercel
  streaming: 'allow',
})

export const runtime = 'nodejs'
export const maxDuration = 300
