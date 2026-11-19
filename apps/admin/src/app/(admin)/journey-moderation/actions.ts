'use server'

import { createHash } from 'node:crypto'
import { headers } from 'next/headers'
import { deriveOperatorContext, moderationOrigin } from '@/lib/journey-moderation/action-contracts'
import { runJourneyModerationAction } from '@/lib/journey-moderation/actions-core'
import { loadJourneyModerationOperator } from '@/lib/journey-moderation/server'
import { JourneyModerationError } from '@/lib/journey-moderation/service'

export async function journeyModerationAction(raw: unknown) {
  return runJourneyModerationAction(raw, {
    load: async () => {
      const bound = await loadJourneyModerationOperator()
      const requestHeaders = await headers()
      const host = requestHeaders.get('host') ?? ''
      // Only a namespace, never authority or a fetch destination. Next checks
      // Server Action origins; Auth/role/live session remain the authorization.
      if (!host || /[@/?#\s\\]/u.test(host)) throw new JourneyModerationError('invalid')
      const authority = new URL(`https://${host}`)
      const local = ['localhost', '127.0.0.1', '[::1]'].includes(authority.hostname)
      authority.protocol = local ? 'http:' : 'https:'
      const origin = moderationOrigin.parse(authority.origin)
      const context = await deriveOperatorContext(bound.identity, origin, async (value) =>
        createHash('sha256').update(value).digest('hex'),
      )
      return { context, service: bound.service }
    },
  })
}
