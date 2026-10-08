import { type SelectableCoachPersonality, selectableCoachPersonalitySchema } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'

export type FlowCoachStyle =
  | { status: 'selected'; code: SelectableCoachPersonality }
  | { status: 'missing' | 'invalid' | 'unavailable' }

const preferenceSchema = z.object({
  user_id: z.string(),
  personality_code: selectableCoachPersonalitySchema,
})

function diagnose(reason: 'invalid_row' | 'ownership' | 'query_error' | 'query_rejected'): void {
  // Optional diagnostics never turn an unavailable style into a failed chat.
  try {
    console.warn('[mobile-flow] coach_style_unapplied', { reason })
  } catch {
    // No row, user identity or database error is emitted or persisted.
  }
}

/** Optional read only. No shared cache, repair write or fallback attribution. */
export async function loadFlowCoachStyle(
  supabase: ServiceClient,
  userId: string,
): Promise<FlowCoachStyle> {
  try {
    // Generated DB types do not yet contain the existing coach domain table.
    const { data, error } = await (
      supabase as unknown as {
        from(table: string): {
          select(columns: string): {
            eq(
              column: string,
              value: string,
            ): {
              maybeSingle(): Promise<{ data: unknown; error: unknown }>
            }
          }
        }
      }
    )
      .from('user_coach_preferences')
      .select('user_id, personality_code')
      .eq('user_id', userId)
      .maybeSingle()
    if (error) {
      diagnose('query_error')
      return { status: 'unavailable' }
    }
    if (data === null) return { status: 'missing' }
    const parsed = preferenceSchema.safeParse(data)
    if (!parsed.success) {
      diagnose('invalid_row')
      return { status: 'invalid' }
    }
    if (parsed.data.user_id !== userId) {
      diagnose('ownership')
      return { status: 'invalid' }
    }
    return { status: 'selected', code: parsed.data.personality_code }
  } catch {
    diagnose('query_rejected')
    return { status: 'unavailable' }
  }
}

const styleLines: Record<SelectableCoachPersonality, string> = {
  focus: 'Tom Focus: direto e objetivo, sem dureza ou bronca.',
  impulse: 'Tom Impulse: energético e positivo, sem pressão ou exagero.',
  zen: 'Tom Zen: calmo, acolhedor e preciso, sem perder clareza.',
}

/** Style changes only wording; the fixed channel policy and clinical data stand. */
export function flowCoachStyleLine(style: FlowCoachStyle | undefined): string {
  if (style?.status !== 'selected') return ''
  return `${styleLines[style.code]} O estilo muda somente o tom; preserve fatos, metas oficiais, restrições e confirmações.`
}
