import {
  loadFlowDayStatusContext,
  type MobileFlowClinicalPort,
  processAuthenticatedMessage,
} from '@mpp/agent'
import { OpenRouterLLM } from '@mpp/providers'
import { closeOpenDaysOnRequest } from './day-close-on-request'
import { type FlowAgent, summarizeFlowToolCalls } from './flow-chat-service'
import { loadToday } from './read-model'
import type { MobileRouteContext } from './route'

/** Each reply owns its provider; a deterministic status never materializes it. */
export function createFlowAgent(
  context: MobileRouteContext,
  clinical?: MobileFlowClinicalPort,
): FlowAgent {
  return {
    async reply(input) {
      if (input.userId !== context.auth.userId) throw new Error('Flow authenticated owner mismatch')
      let llm: OpenRouterLLM | undefined
      const output = await processAuthenticatedMessage(
        {
          supabase: context.supabase,
          ...(clinical ? { flowClinical: clinical } : {}),
          get llm() {
            if (!llm) {
              const apiKey = process.env.OPENROUTER_API_KEY
              if (!apiKey) throw new Error('Flow provider is not configured')
              llm = new OpenRouterLLM({
                apiKey,
                heliconeApiKey: process.env.HELICONE_API_KEY,
                appName: 'Performe AI Flow',
              })
            }
            return llm
          },
          async loadFlowDayStatus(userId, text, timestamp) {
            if (userId !== context.auth.userId) throw new Error('Flow authenticated owner mismatch')
            await closeOpenDaysOnRequest(context, { now: timestamp })
            return loadFlowDayStatusContext(context.supabase, userId, text, timestamp, {
              timezone: context.auth.patient.timezone ?? 'UTC',
              readToday: loadToday,
            })
          },
        },
        input,
      )
      if (output.text.trim().length === 0) {
        console.error('[mobile-flow] empty_reply_detail', {
          completion_tokens: output.completionTokens,
          tool_calls: JSON.stringify(summarizeFlowToolCalls(output.toolCalls)),
        })
      }
      return {
        text: output.text,
        ...(output.flowStatusPhrase ? { flowStatusPhrase: output.flowStatusPhrase } : {}),
        metadata: {
          stage: output.stage,
          modelUsed: output.modelUsed,
          promptTokens: output.promptTokens,
          completionTokens: output.completionTokens,
          costUsd: output.costUsd,
          latencyMs: output.latencyMs,
        },
      }
    },
  }
}
