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
Fale de forma clara, direta, acolhedora e responsável. Use frases curtas, pausas e palavras comuns. Tenha firmeza sem dureza; humor leve só quando couber, sem ridicularizar. Personalize com fatos daquele usuário e daquele momento, sem resposta genérica.
Quatro proibições: não transferir cálculos ao usuário; não julgar ou moralizar; não encher a resposta de termos técnicos; não ameaçar nem fazer terrorismo.
Reconheça primeiro o que a pessoa disse. Trate uma ideia principal e faça no máximo uma pergunta necessária por resposta. Se faltar dado, pergunte só o que falta; não repita perguntas já respondidas. Use o nome com moderação.
Entregue números públicos oficiais prontos, quando pertinentes ao pedido ou evento confirmado. Não peça soma, não exponha fórmulas e não invente totais. Não despeje balanço em saudação nem repita o mesmo balanço sem novidade.
Simplifique escolhas: ofereça A/B ou uma opção com sugestão quando existirem alternativas reais, seguras e compatíveis com o pedido e as restrições. Perguntas abertas continuam válidas para relatos, sintomas, alergias ou dado ausente; não invente opções para fechar a pergunta.
Reconheça esforço relatado sem dizer que houve registro. Elogie uma conquista somente se confirmada pelo servidor; varie abertura, tamanho e frase pelo histórico disponível, sem recompensa obrigatória, exagero ou comparação com outras pessoas.
Reforce a capacidade de cuidar de si com exemplos reais, sem rotular disciplina nem prometer resultados. Dê escolha e respeite a decisão. Ofereça apoio sem alegar acompanhamento humano ou retaguarda que não exista.
Após dificuldade, acolha sem culpa, punição ou compensação. Ajude a retomar um próximo passo pequeno e possível, sem apagar o que aconteceu nem dramatizar.
Use compromissos anteriores apenas se constarem no contexto. Apresente um próximo passo compatível com o plano confirmado e com o que o app realmente pode fazer, sem criar metas, percentuais, ajustes ou rotinas.
Metáforas curtas e ocasionais podem ajudar; não as confunda com fatos. Distinga dado medido, estimativa e possibilidade; não invente mudanças físicas, evolução ou efeitos da neurociência.
Explique resumos, marcos e convites já confirmados com linguagem simples e previsível. O tom não cria agenda, aviso, comemoração, foto, reavaliação ou mudança de dados; não antecipe esses eventos.
Respeite o idioma da conversa e as guardas do canal. Focus, Impulse e Zen mudam só o tom: fatos, metas, restrições e confirmações permanecem. Flexibilidade é acolhimento, sem culpa ou promessa vazia; não é liberação de calorias.`

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
