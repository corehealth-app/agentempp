/**
 * Comentário educativo pós-registro (Roberto 2026-06-01).
 *
 * Após a Fase 1 (registro determinístico), Roberto sentiu falta do comentário
 * de 2-4 frases que o LLM redigia depois do card. Era a peça neurocomportamental
 * do método MPP: microvitória → identidade → orientação com tato.
 *
 * Solução: 1 chamada LLM PEQUENA pós-determinístico, só pro comentário. Usa
 * Haiku (barato, rápido). Prompt focado em poucos kbs (não os 52k do system
 * prompt completo). Se falhar/timeout, retorna '' e msg vai sem o comentário
 * (degradação graciosa — nunca bloqueia o registro).
 */
import type { OpenRouterLLM } from '@mpp/providers'

const SYSTEM_PROMPT = `Você é o Dr. Roberto Menescal, nutricionista que conduz o Método MPP via WhatsApp.

REGRA EDUCAÇÃO ALIMENTAR PÓS-REFEIÇÃO (do manual MPP §2 — Princípios Neurocomportamentais):

Após cada refeição/treino registrado, escreva um comentário de 2-4 frases seguindo ESTA ORDEM:

1. MICROVITÓRIA (§2.1) — abra celebrando o que o paciente fez de CERTO, ancorado num número real da refeição/treino. Registrar já é progresso. VARIE o elogio (§2.7 — elogio repetido anestesia o cérebro). Use ângulos diferentes: aporte proteico, custo-benefício, saciedade, comparação, escolha consciente.

2. REFORÇO DE IDENTIDADE (§2.3) — conecte com QUEM o paciente está se tornando. NÃO elogie o comportamento isolado, reforce a identidade de pessoa consistente/disciplinada.

3. ORIENTAÇÃO (rodapé — secundária, NUNCA manchete) — só DEPOIS de microvitória + identidade. Use a heurística:
   - Aliado: proteína > 15g/100g, gordura < 8g/100g (carnes magras, frango, peixe, ovos, whey, iogurte natural)
   - Cuidado-carboidrato: > 20g/100g (arroz, massa, pão, batata, doces)
   - Cuidado-gordura: > 15g/100g (queijos amarelos, embutidos, frituras, oleaginosas)
   Se aparecer cuidado-carb ou cuidado-gordura, sinalize com TATO e ofereça ALTERNATIVA concreta ("da próxima, trocar metade por X" — não só "evita Y").

REGRAS INVIOLÁVEIS:
- 2-4 frases TOTAL, conversa de amigo, não relatório.
- ESCREVA POR EXTENSO: "proteína" e "carboidrato" (NUNCA "P", "C", "G" na prosa — Roberto pediu explicitamente).
- NÃO repita números do card de balanço (consumido, restam, bloco 7700) — esses já apareceram acima.
- Pode citar macros DO ITEM específico ("65g de proteína nessa costela") — isso ancora a microvitória.
- NÃO inclua emojis decorativos (use só se naturalmente couber).
- NÃO repita a tabela nem o card.
- Tom direto, próximo. Sem moralismo, sem proibição.
- Se a refeição foi clara fora do padrão: ACOLHIMENTO (§2.8) — normalize, redirecione, reforce identidade. NUNCA puna.
- Pra treino: foque em consistência, esforço, contribuição pro bloco. Mesma estrutura (microvitória + identidade + orientação se couber, ex: "da próxima, força > caminhada pra ganhar mais massa").

Responda APENAS o comentário (sem cabeçalho, sem prefixo, sem repetir tabela/card).`

export interface EduCommentInput {
  /** Tipo da refeição registrada (ou 'treino' pra exercício). */
  kind: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | 'outro' | 'treino'
  /** Itens registrados nesse turno (refeição) com macros. */
  items?: Array<{
    food_name: string
    quantity_g: number
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
  }>
  /** Total da refeição registrada. */
  totals?: { kcal: number; protein_g: number; carbs_g: number; fat_g: number }
  /** Pra treino: tipo + duração + kcal. */
  workout?: { type: string; durationMin?: number | null; kcalBurned: number }
  /** Protocolo do paciente — modula tom (recomp foca massa, manutenção foca consistência, etc). */
  protocol?: 'recomposicao' | 'manutencao' | 'ganho_massa' | null
  /** Locale pra idioma da resposta. */
  locale?: string | null
}

export interface EduCommentOpts {
  /** Default 'anthropic/claude-haiku-4.5' — barato e rápido. */
  model?: string
  /** Timeout em ms. Default 8000 — passou disso, devolve '' sem bloquear o registro. */
  timeoutMs?: number
}

export async function generateEducationalComment(
  llm: OpenRouterLLM,
  input: EduCommentInput,
  opts: EduCommentOpts = {},
): Promise<string> {
  const model = opts.model ?? 'anthropic/claude-haiku-4.5'
  const timeoutMs = opts.timeoutMs ?? 8000

  const userPayload = formatUserPayload(input)

  try {
    const llmPromise = llm.complete({
      model,
      systemPrompt: SYSTEM_PROMPT,
      messages: [{ role: 'user', content: userPayload }],
      temperature: 0.6,
      maxTokens: 300,
      metadata: { Stage: 'edu-comment' },
    })
    const timeoutPromise = new Promise<null>((resolve) => setTimeout(() => resolve(null), timeoutMs))
    const result = await Promise.race([llmPromise, timeoutPromise])
    if (result === null) return ''
    const content = (result.content ?? '').trim()
    // Sanity: remove markdown extra acidental e mantém só 1ª linha-bloco
    return content.replace(/^\s*```[\s\S]*?```\s*/g, '').trim()
  } catch {
    // Erro de LLM (saldo, timeout, parser) — degradação graciosa, sem comentário
    return ''
  }
}

function formatUserPayload(input: EduCommentInput): string {
  const lang = input.locale === 'es' ? 'español' : input.locale === 'en' ? 'English' : 'português'
  const protocol = input.protocol ?? 'recomposicao'

  if (input.kind === 'treino') {
    const w = input.workout
    return `Idioma: ${lang}
Protocolo: ${protocol}
Turno: TREINO registrado.
Tipo: ${w?.type ?? 'treino'}
Duração: ${w?.durationMin ?? '?'} min
Gasto estimado: ${w?.kcalBurned ?? 0} kcal

Escreva o comentário de 2-4 frases (microvitória → identidade → orientação se couber).`
  }

  const itemsTxt =
    (input.items ?? [])
      .map(
        (it) =>
          `- ${it.food_name} (${it.quantity_g}g): ${it.kcal} kcal | proteína ${it.protein_g}g | carboidrato ${it.carbs_g}g | gordura ${it.fat_g}g`,
      )
      .join('\n') || '(sem itens)'
  const t = input.totals ?? { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 }

  return `Idioma: ${lang}
Protocolo: ${protocol}
Turno: REFEIÇÃO registrada (${input.kind}).
Itens:
${itemsTxt}
Total da refeição: ${t.kcal} kcal | proteína ${t.protein_g}g | carboidrato ${t.carbs_g}g | gordura ${t.fat_g}g

Escreva o comentário de 2-4 frases (microvitória → identidade → orientação com tato se houver cuidado-carb ou cuidado-gordura).`
}
