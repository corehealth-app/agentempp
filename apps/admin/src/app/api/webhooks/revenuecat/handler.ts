import type { EntitlementPlan } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import {
  normalizeRevenueCatEvent,
  parseRevenueCatProductPlanMap,
  type RevenueCatNormalizationConfiguration,
  RevenueCatWebhookError,
  verifyRevenueCatSignature,
} from '@/lib/billing/revenuecat-webhook'
import { createServiceClient } from '@/lib/supabase/server'

const MAX_WEBHOOK_BYTES = 256 * 1024

type RevenueCatWebhookConfiguration = RevenueCatNormalizationConfiguration & {
  signingSecret: string
  productPlanMap: Record<string, EntitlementPlan>
}

export type RevenueCatWebhookRuntime = {
  now(): Date
  createServiceClient(): ServiceClient
  configuration: RevenueCatWebhookConfiguration | null
}

function loadConfiguration(): RevenueCatWebhookConfiguration | null {
  const signingSecret = process.env.REVENUECAT_WEBHOOK_SIGNING_SECRET
  const environment = process.env.REVENUECAT_WEBHOOK_ENVIRONMENT
  const productPlanMap = process.env.REVENUECAT_PRODUCT_PLAN_MAP
  if (!signingSecret || !environment || !productPlanMap) return null
  if (signingSecret.length < 32) return null
  if (environment !== 'sandbox' && environment !== 'production') return null

  try {
    return {
      signingSecret,
      expectedEnvironment: environment,
      entitlementKey: 'bodyflow_full',
      productPlanMap: parseRevenueCatProductPlanMap(productPlanMap),
    }
  } catch {
    return null
  }
}

const defaultRuntime: RevenueCatWebhookRuntime = {
  now: () => new Date(),
  createServiceClient,
  get configuration() {
    return loadConfiguration()
  },
}

function jsonResponse(body: unknown, status: number): Response {
  return Response.json(body, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
    },
  })
}

async function readBoundedRawBody(request: Request): Promise<string> {
  const contentLength = request.headers.get('content-length')
  if (contentLength && Number(contentLength) > MAX_WEBHOOK_BYTES) {
    throw new RevenueCatWebhookError(413, 'request_too_large', 'Webhook body is too large')
  }
  if (!request.body) {
    throw new RevenueCatWebhookError(400, 'invalid_payload', 'Webhook body is required')
  }

  const reader = request.body.getReader()
  const decoder = new TextDecoder('utf-8', { fatal: true })
  let bytes = 0
  let body = ''
  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      bytes += value.byteLength
      if (bytes > MAX_WEBHOOK_BYTES) {
        await reader.cancel().catch(() => undefined)
        throw new RevenueCatWebhookError(413, 'request_too_large', 'Webhook body is too large')
      }
      body += decoder.decode(value, { stream: true })
    }
    body += decoder.decode()
  } catch (error) {
    if (error instanceof RevenueCatWebhookError) throw error
    throw new RevenueCatWebhookError(400, 'invalid_payload', 'Webhook body is invalid')
  }
  return body
}

export function createRevenueCatWebhookHandler(runtimeValue = defaultRuntime) {
  return async function handleRevenueCatWebhook(request: Request): Promise<Response> {
    const configuration = runtimeValue.configuration
    if (!configuration) {
      return jsonResponse({ ok: false, error: 'provider_not_configured' }, 503)
    }
    if (!/^application\/json(?:\s*;.*)?$/i.test(request.headers.get('content-type') ?? '')) {
      return jsonResponse({ ok: false, error: 'unsupported_media_type' }, 415)
    }

    try {
      const rawBody = await readBoundedRawBody(request)
      verifyRevenueCatSignature({
        body: rawBody,
        header: request.headers.get('x-revenuecat-webhook-signature'),
        secret: configuration.signingSecret,
        now: runtimeValue.now(),
      })

      let payload: unknown
      try {
        payload = JSON.parse(rawBody)
      } catch {
        throw new RevenueCatWebhookError(400, 'invalid_payload', 'Invalid RevenueCat payload')
      }

      const normalized = normalizeRevenueCatEvent(payload, configuration)
      if (normalized.kind === 'ignored') {
        return jsonResponse({ ok: true, result: 'ignored' }, 200)
      }

      const event = normalized.event
      const rpcArguments = {
        p_provider_event_id: event.event_id,
        p_event_type: event.event_type,
        p_user_id: event.user_id,
        p_entitlement_key: event.entitlement_key,
        p_source: event.source,
        p_source_reference: event.source_reference,
        p_status: event.status,
        p_plan: event.plan,
        p_environment: event.environment,
        p_occurred_at: event.occurred_at,
        p_starts_at: event.starts_at,
        p_access_expires_at: event.access_expires_at,
        p_grace_expires_at: event.grace_expires_at,
        p_cancel_at_period_end: event.cancel_at_period_end,
        p_reason_code: null,
        p_actor_id: null,
      }
      // Generated RPC types do not preserve nullable PostgreSQL function arguments.
      const { data, error } = await runtimeValue
        .createServiceClient()
        .rpc('apply_entitlement_event', rpcArguments as never)
      if (error) return jsonResponse({ ok: false, error: 'persistence_failed' }, 500)

      const result = (data as { result?: unknown } | null)?.result
      if (result !== 'applied' && result !== 'duplicate' && result !== 'stale') {
        return jsonResponse({ ok: false, error: 'persistence_failed' }, 500)
      }
      return jsonResponse({ ok: true, result }, 200)
    } catch (error) {
      if (error instanceof RevenueCatWebhookError) {
        return jsonResponse({ ok: false, error: error.code }, error.status)
      }
      return jsonResponse({ ok: false, error: 'internal_error' }, 500)
    }
  }
}
