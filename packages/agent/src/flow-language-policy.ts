import { createHash } from 'node:crypto'
import { protocolPhaseExplanation } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { filterAndFormatRules, normalizeRuleLang, type RuleRow } from './prompt-rules.js'

// Only these six exact staging versions were reviewed on 2026-10-08.
// Digest: UTF-8 JSON.stringify([slug, tipo, language, topic, content]).
// A new/changed rule is never silently discarded or treated as reviewed.
const reviewedRules = new Map([
  [
    'persona-master-dr-roberto-amigo-coach',
    'f9f5de802f7632822e75468e893614d619161e36b156267aac586e184f391c63',
  ],
  [
    'quando-mostrar-balanco-diario',
    '47dd6442053fed178af9d45753b6b01a666663879cf9ce2578175593a4e50709',
  ],
  [
    'confirmacao-pais-residencia',
    'afe99f4a504f2cd3c933b010f91d589488e268e4d75a40b15e7a716b3203b203',
  ],
  ['saudacoes-variadas', 'b3be74bc7d51b6645e39d0e4f33a92813f248bc7c984518b1d287b07b60046ab'],
  ['idioma-do-paciente', 'f5bbc74c9d2fb49c886460f717f4e08bbd8af67e898d67bad5ae9bc693131925'],
  ['decisoes-com-confirmacao', '9f00e29b7cd0fe73324ef4529085dbca2a1044b0360bc027e0c58ca8f75d4099'],
])

type FlowRuleRow = RuleRow & { slug?: unknown; tipo?: unknown }

interface FlowLanguageRules {
  /** null preserves the already-read view fallback; '' is a valid projection. */
  systemPrompt: string | null
  applied: boolean
}

function diagnose(reason: string): void {
  try {
    console.warn('[mobile-flow] language_card_unapplied', { reason })
  } catch {
    // Logging must not replace the turn's outcome. No rule or user text.
  }
}

function validRule(row: unknown): row is FlowRuleRow {
  if (typeof row !== 'object' || row === null) return false
  const candidate = row as Record<string, unknown>
  return (
    typeof candidate.topic === 'string' &&
    typeof candidate.content === 'string' &&
    (typeof candidate.language === 'string' || candidate.language === null)
  )
}

/** Flow only. Same two reads as before (view + rules); no fallback re-query. */
export async function loadFlowLanguageRules(
  supabase: ServiceClient,
  stage: string,
  locale: string | null | undefined,
): Promise<FlowLanguageRules> {
  const { data, error } = await supabase
    .from('agent_rules')
    .select('topic, content, language, slug, tipo')
    .eq('status', 'active')
    .or(`tipo.eq.regras_gerais,tipo.eq.${stage}`)
    .order('display_order', { ascending: true })
  if (error || !Array.isArray(data) || data.length === 0 || !data.every(validRule)) {
    diagnose(error ? 'query_error' : 'missing_or_malformed_rows')
    return { systemPrompt: null, applied: false }
  }

  const lang = normalizeRuleLang(locale)
  const rows: FlowRuleRow[] = data
  const general = rows.filter((row) => row.tipo === 'regras_gerais')
  const seen = new Set<string>()
  const reviewed =
    general.length === reviewedRules.size &&
    rows.every((row) => {
      if (row.tipo !== 'regras_gerais') return row.tipo === stage
      if (typeof row.slug !== 'string' || seen.has(row.slug)) return false
      seen.add(row.slug)
      const digest = createHash('sha256')
        .update(JSON.stringify([row.slug, row.tipo, row.language, row.topic, row.content]))
        .digest('hex')
      return reviewedRules.get(row.slug) === digest
    })
  if (!reviewed) {
    diagnose('rule_versions_unreviewed')
    return { systemPrompt: filterAndFormatRules(rows, lang), applied: false }
  }

  // Project whole tuples, never split content on a Markdown separator:
  // unknown phase content can legitimately quote an old general block.
  const phaseRules = rows.filter((row) => row.tipo !== 'regras_gerais')
  return { systemPrompt: filterAndFormatRules(phaseRules, lang) ?? '', applied: true }
}

const languageCard = `### Linguagem do Flow
Seja claro, direto, acolhedor e responsável; frases curtas e palavras comuns. Firmeza sem dureza, humor sem ridicularizar, personalização por fatos do usuário e do momento.
Quatro proibições: não transferir cálculos ao usuário; não julgar ou moralizar; não encher a resposta de termos técnicos; não ameaçar nem fazer terrorismo.
Reconheça primeiro; uma ideia e no máximo uma pergunta necessária. Pergunte só o dado ausente, não repita perguntas já respondidas; nome com moderação.
Entregue números públicos oficiais pertinentes, sem soma, fórmula ou total inventado. Não mostre balanço em saudação nem o repita sem novidade.
A/B ou sugestão só com opções reais, seguras e compatíveis com pedido e restrições. Relato, sintoma, alergia e dado ausente admitem pergunta aberta; não invente opções.
Esforço relatado não é registro; conquista exige confirmação do servidor. Varie pelo histórico, sem elogio ou recompensa obrigatórios, exagero ou comparação.
Reforce autonomia com exemplos reais, sem rótulo ou promessa. Respeite escolhas; apoio não significa acompanhamento humano inexistente.
Acolha dificuldade e ajude no próximo passo possível, sem culpa, punição, compensação, apagar o ocorrido ou dramatizar.
Compromisso só no contexto; próximo passo compatível com plano confirmado e capacidade real do app. Não crie metas, percentuais, ajustes ou rotinas.
Metáfora curta não é fato. Distinga medido, estimativa e possibilidade; não invente mudança física, evolução ou efeito de neurociência.
Explique resumos, marcos e convites confirmados com simplicidade e previsibilidade. O tom não cria nem antecipa agenda, aviso, comemoração, foto, reavaliação ou mudança de dados.
Respeite idioma e guardas do canal. Focus, Impulse e Zen só mudam o tom; fatos, metas, restrições e confirmações ficam. Flexibilidade é acolhimento, sem culpa ou promessa vazia; não libera calorias.
Definições educativas do método; não são prescrição individual nem obrigação universal:
HIIT: intervalos curtos muito intensos intercalados com descanso ativo/leve; útil para condicionamento e gasto agudo, mas não substitui musculação.
Proteína: tijolo do músculo; melhora saciedade; distribuir em 3–5 refeições/dia.
EPOC: consumo extra de oxigênio pós-exercício; o app não inclui uma parcela separada no balanço nem libera calorias por essa explicação.`

/** Fixed source facts, never a transition, target change or eligibility decision. */
function phaseCard(protocol: unknown): string {
  let label: string
  switch (protocol) {
    case 'recomposicao':
      label = 'recomposição corporal.'
      break
    case 'ganho_massa':
      label = 'ganho de massa.'
      break
    case 'manutencao':
      label = 'manutenção.'
      break
    default:
      return ''
  }
  return `### Fase atual do Flow\nObjetivo registrado: ${label}\n\n${protocolPhaseExplanation(protocol).join('\n\n')}`
}

/** Single composition path, only after the versioned rules were reviewed. */
export function flowLanguageCards(protocol: unknown, hasAssistantHistory: boolean) {
  const phase = phaseCard(protocol)
  return {
    stable: languageCard + (phase ? `\n\n${phase}` : ''),
    situation: hasAssistantHistory
      ? '### Situação deste turno\nNão repita aberturas ou balanços das últimas respostas do histórico. Se a pessoa só cumprimentou e nada mudou, responda curto. Varie a saudação quando fizer sentido.'
      : '',
    // No trusted button origin exists in AuthenticatedAgentInput today.
  }
}
