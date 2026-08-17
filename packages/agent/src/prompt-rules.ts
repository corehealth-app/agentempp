/**
 * Filtro de idioma das agent_rules (economia de token #1 — Roberto 2026-05-27).
 *
 * A view v_active_prompts agrega TODAS as regras ativas (pt-BR + en + es) em
 * todo turno. Este helper re-agrega as regras do stage filtrando pelo idioma do
 * paciente: mantém pt-BR (base do método) + idioma do paciente + agnóstico
 * (language null); descarta as duplicatas localizadas de OUTRO idioma. Paciente
 * pt-BR (todos hoje) perde as ~16 regras en/es por turno, sem perder nada.
 *
 * Formato IDÊNTICO ao da view (verificado): '## ' || topic || E'\n\n' || content,
 * juntado por E'\n\n---\n\n', ordem display_order. Só dropa os blocos de idioma
 * estranho. Fonte única usada pelo pipeline (conversa) e pelo engajamento (matinal).
 */
import type { ServiceClient } from '@mpp/db'

/** locale do paciente → idioma das regras ('pt-BR' default). */
export function normalizeRuleLang(locale: string | null | undefined): 'pt-BR' | 'en' | 'es' {
  const l = (locale ?? '').toLowerCase()
  if (l.startsWith('en')) return 'en'
  if (l.startsWith('es')) return 'es'
  return 'pt-BR'
}

export interface RuleRow {
  topic: string
  content: string
  language: string | null
}

function normalizeStoredRuleLang(language: string | null): string | null {
  if (language == null) return null
  const normalized = language.trim().toLowerCase()
  if (normalized === 'pt' || normalized === 'pt-br') return 'pt-BR'
  if (normalized === 'en' || normalized.startsWith('en-')) return 'en'
  if (normalized === 'es' || normalized.startsWith('es-')) return 'es'
  return language
}

/**
 * Parte pura (testável): filtra por idioma e agrega no formato da view.
 * Mantém pt-BR (base) + idioma do paciente + agnóstico (null). Retorna null se
 * nada sobrar (caller cai no prompt cheio).
 */
export function filterAndFormatRules(rows: RuleRow[], lang: 'pt-BR' | 'en' | 'es'): string | null {
  const kept = rows.filter((r) => {
    const ruleLang = normalizeStoredRuleLang(r.language)
    return ruleLang == null || ruleLang === 'pt-BR' || ruleLang === lang
  })
  if (kept.length === 0) return null
  return kept.map((r) => `## ${r.topic}\n\n${r.content}`).join('\n\n---\n\n')
}

/**
 * Re-agrega as agent_rules ativas do stage filtrando pelo idioma do paciente.
 * Retorna null se não houver regras (o caller deve cair no prompt cheio da view).
 */
export async function loadFilteredSystemPrompt(
  supabase: ServiceClient,
  stage: string,
  locale: string | null | undefined,
): Promise<string | null> {
  const { data: rules } = await supabase
    .from('agent_rules')
    .select('topic, content, language')
    .eq('status', 'active')
    .or(`tipo.eq.regras_gerais,tipo.eq.${stage}`)
    .order('display_order', { ascending: true })
  return filterAndFormatRules((rules ?? []) as RuleRow[], normalizeRuleLang(locale))
}
