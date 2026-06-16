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

REGRAS NOVAS (Roberto 2026-06-03):

A) **SEMPRE NOMEIE O ITEM ao orientar — NUNCA "o item de Xg"**
   ❌ ERRADO: "reduz um pouco o item de 100g (que tem 28g de carb)"
   ✅ CERTO: "reduz um pouco o arroz (28g de carboidrato em 100g)"
   Se citar quantidade/macro pra orientar, SEMPRE inclua o NOME do alimento que você está
   se referindo. Sem nome, paciente não sabe o que reduzir.

B) **SUBSTITUIÇÕES PRECISAM SER COERENTES COM O TIPO DE REFEIÇÃO**
   O paciente não vai trocar farofa por maçã, não vai trocar brigadeiro por brócolis,
   não vai comer arroz com iogurte. As sugestões têm que fazer sentido DENTRO do prato:
   ✅ "Farofa com bacon → farofa sem bacon" (mesma família, menos gordura)
   ✅ "Pão branco → pão integral" (mesma função no café)
   ✅ "Fritura → versão assada do mesmo prato"
   ✅ "Coxa com pele → coxa sem pele" (mesma proteína, menos gordura)
   ❌ "Farofa → maçã" (não combina com feijoada)
   ❌ "Sorvete → ovo" (refeições/momentos totalmente diferentes)
   ❌ "Brigadeiro → brócolis" (sobremesa ≠ acompanhamento de almoço)
   Pense: o paciente vai TROCAR isso de verdade na próxima vez que comer o mesmo prato?

C) **REFEIÇÕES "FORA DO PADRÃO" OCASIONAIS — NÃO SUGIRA SUBSTITUIÇÃO**
   Se o paciente comeu sorvete, doce, fast food, pizza — algo claramente OCASIONAL
   (não rotina) — NÃO ofereça substituição. Em vez disso, normalize + reforce identidade:
   ✅ "Sorvete num jantar mais leve — às vezes a gente come algo mais calórico e tudo
       bem, isso não vira rotina pra quem mantém o ritmo como você."
   ✅ "Pizza num final de semana cabe no processo. O que importa é o padrão da semana,
       não 1 refeição."
   ❌ "Pizza tem muito carboidrato — da próxima troca por salada"
       (não vai trocar, e o tom é moralista)

   MPP é solução pra VIDA TODA, inclusive manutenção. Paciente NÃO vai parar de comer
   sorvete, pizza, doce pra sempre. Reconheça o ocasional como ocasional sem julgar.

D) **NUNCA TROQUE O TIPO DE REFEIÇÃO**
   Lanche ≠ jantar. Sobremesa ≠ proteína principal. Não sugira "troque sobremesa por
   ovo" — o paciente queria sobremesa, não proteína.

REGRAS NOVAS (Roberto 2026-06-09):

E) **NUNCA INVENTE ITEM QUE NÃO ESTÁ NA LISTA — INVIOLÁVEL**
   ❌ Bug observado: paciente comeu "leite com whey + ovo frito + pão francês + geleia
       + queijo mussarela". Comentário disse "reduz um pouco da manteiga ou do óleo
       que tempera os itens". MANTEIGA E ÓLEO NÃO ESTAVAM NA LISTA.
   ✅ A orientação SÓ pode mencionar itens que APARECEM na lista da refeição. Se a
       gordura está alta mas você não sabe qual item específico cortar, NÃO INVENTE.
       Identifique o item de maior gordura/100g na lista e sugira reduzir AQUELE.
   ✅ Não use frases vagas tipo "aquele item com 29g de carboidrato em 50g" — isso
       é o mesmo que dizer "o item" (regra A). Sempre NOMEIE.

F) **SEPARE EM PARÁGRAFOS — INVIOLÁVEL** (manual MPP § estrutura)
   Em vez de uma frase corrida que mistura microvitória + identidade + orientação,
   USE QUEBRA DE LINHA pra separar:

   Parágrafo 1: MICROVITÓRIA + IDENTIDADE (1 frase ou 2 curtas, fluindo).
   [LINHA EM BRANCO]
   Parágrafo 2: ORIENTAÇÃO (1 frase, opcional — só se houver cuidado-carb/cuidado-gordura).

   ❌ ERRADO (frase corrida, tudo junto):
   "Café com 44g de proteína — começo forte. Você está construindo o hábito de
    priorizar proteína. O carboidrato ficou elevado (52g) — da próxima reduz o pão."

   ✅ CERTO (parágrafos separados):
   "Café com 44g de proteína — começo forte. Você está construindo o hábito de
    priorizar proteína mesmo nos momentos descontraídos.

    O carboidrato ficou um pouco alto (52g) — na próxima, considera reduzir o pão
    francês (29g de carboidrato pra 50g) pela metade."

   Roberto pediu explicitamente: SEPARAR a frase de educação da frase de elogio.

Responda APENAS o comentário (sem cabeçalho, sem prefixo, sem repetir tabela/card).`

/**
 * Adapta items do tool registra_refeicao (chave `name`) pro shape do
 * EduCommentInput (`food_name`). DRY pros callers — antes cada um repetia
 * o map com cast, e o cast TS mascarava o mismatch em runtime (P0 bug
 * 2026-06-13: catch silencioso + items[].name vs items[].food_name).
 *
 * Aceita os dois shapes (tool result tem `name`, payload do edu tem
 * `food_name`) — primeiro que estiver presente vence, vazio cai no
 * hardening invalid_anchor_shape do selector.
 */
export function adaptToolItemsToEduInput(
  items:
    | Array<{
        name?: string
        food_name?: string
        quantity_g: number
        kcal?: number
        protein_g?: number
        carbs_g?: number
        fat_g?: number
      }>
    | undefined
    | null,
): EduCommentInput['items'] {
  if (!items) return undefined
  return items.map((i) => ({
    food_name: (i.name ?? i.food_name ?? '') as string,
    quantity_g: i.quantity_g,
    kcal: i.kcal ?? 0,
    protein_g: i.protein_g ?? 0,
    carbs_g: i.carbs_g ?? 0,
    fat_g: i.fat_g ?? 0,
  }))
}

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
  /** Supabase pra tentar curated phrase ANTES de chamar Haiku (Sprint 3.1
   * — Roberto 2026-06-11). Quando disponível, consulta
   * `food_education_phrases` e usa frase curada se houver. Senão cai pro Haiku. */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  supabase?: any
  userId?: string
  state?: {
    protocol?: 'recomposicao' | 'manutencao' | 'ganho_massa' | null
    protein_pct?: number
    kcal_pct?: number
    deficit_block_pct?: number
  }
  /** Embeddings provider pra cascade semântica do curated-phrase selector.
   * Quando ausente, selector usa só .eq() exato (degradação graciosa). */
  embeddings?: { embed(text: string): Promise<number[]> }
}

/**
 * Telemetria edu-comment (audit P2 2026-06-13): cada ponto do funil grava
 * product_event. Antes era cego — impossível distinguir curated_hit de
 * timeout de phantom_drop. Try/catch interno garante never-block.
 */
async function emitEdu(
  opts: EduCommentOpts,
  event: string,
  properties: Record<string, unknown>,
): Promise<void> {
  if (!opts.supabase || !opts.userId) return
  try {
    await opts.supabase.from('product_events').insert({
      user_id: opts.userId,
      event,
      properties: { stage: 'edu-comment', ...properties },
    })
  } catch {
    // never block
  }
}

export async function generateEducationalComment(
  llm: OpenRouterLLM,
  input: EduCommentInput,
  opts: EduCommentOpts = {},
): Promise<string> {
  // Defesa interna (bug Roberto 2026-06-16): se a tool deduplicou 100% dos
  // itens (already_logged=true ⇒ items=[]), o composePostRegistrationMessage
  // emite "já estava registrado" SEM tabela — mas o Haiku, sem itens no
  // payload, improvisa contradição ("lanche apareceu zerada, saiu sem comer,
  // lista não carregou"). Treino não tem items (usa workout.*), então só
  // bloqueia refeição vazia. Defesa em camadas com o guard do caller.
  //
  // HARDENING (review HIGH H3 2026-06-16): também bloqueia quando items
  // existe mas TODOS têm kcal=0 ou totals.kcal=0 (calc-failed) — payload
  // tecnicamente populado mas semanticamente zerado vai gerar o mesmo
  // improviso ("aveia saiu zerada").
  if (input.kind !== 'treino') {
    const noItems = !input.items || input.items.length === 0
    const totalsZero =
      input.totals != null &&
      (input.totals.kcal ?? 0) === 0 &&
      (input.totals.protein_g ?? 0) === 0
    const allItemsZeroKcal =
      input.items != null &&
      input.items.length > 0 &&
      input.items.every((it) => (it.kcal ?? 0) === 0)
    if (noItems || totalsZero || allItemsZeroKcal) {
      await emitEdu(opts, 'edu_comment.skipped_empty_items', {
        kind: input.kind,
        reason: noItems ? 'no_items' : totalsZero ? 'totals_zero' : 'all_items_zero_kcal',
      })
      return ''
    }
  }
  const model = opts.model ?? 'anthropic/claude-haiku-4.5'
  // Timeout 12s (audit 2026-06-13): 8s era apertado — Haiku 4.5 com 300 tokens
  // é ~3-5s em cenário ideal, mas P95 com cold start ou roteamento OpenRouter
  // passa de 8s. Custo de esperar mais 4s vale a pena — alternativa é cortar
  // comentário sem aviso.
  const timeoutMs = opts.timeoutMs ?? 12000

  // CURATED PHRASE FIRST (Roberto 2026-06-11): se há frase curada pelo
  // Roberto pro alimento âncora, usa ela em vez de chamar Haiku. Economia
  // ~$8-12/mês quando planilha cobrir top-30 alimentos.
  if (
    opts.supabase &&
    opts.userId &&
    input.kind !== 'treino' &&
    input.items &&
    input.items.length > 0
  ) {
    try {
      const { selectCuratedPhrase } = await import('./curated-phrase-selector.js')
      const curated = await selectCuratedPhrase(opts.supabase, {
        items: input.items,
        userId: opts.userId,
        state: opts.state,
        language: input.locale ?? 'pt-BR',
        // Nível 1 defensivo (bug I3 2026-06-14): passa o slot pra selector
        // descartar frases temporalmente incompatíveis (ex: "Whey de manhã…"
        // em jantar). Sem isso o filtro vira no-op.
        mealKind: input.kind,
        embeddings: opts.embeddings,
      })
      if (curated.phrase) {
        await emitEdu(opts, 'edu_comment.curated_hit', {
          kind: input.kind,
          anchor: curated.food_canonical_name,
          reason: curated.reason,
        })
        return curated.phrase
      }
      // Defesa em camadas (audit P0 2026-06-13): se reason=invalid_anchor_shape
      // significa que o adapter de items quebrou (bug histórico voltou). NÃO
      // pode ser confundido com curated_miss normal — evento dedicado pra
      // dashboard alertar imediatamente em regressão futura.
      if (curated.reason === 'invalid_anchor_shape') {
        await emitEdu(opts, 'edu_comment.adapter_regression', {
          kind: input.kind,
          items_preview: input.items?.slice(0, 3).map((i) => ({
            food_name: i.food_name,
            kcal: i.kcal,
          })),
          severity: 'critical',
        })
      } else {
        // curated_miss legítimo (planilha incompleta) — fire-and-forget,
        // não bloqueia turno do paciente.
        void emitEdu(opts, 'edu_comment.curated_miss', {
          kind: input.kind,
          anchor: curated.food_canonical_name,
          reason: curated.reason,
        })
      }
    } catch (err) {
      // Antes era catch silencioso — bug do shape mismatch (P0 audit) ficou
      // 36h+ invisível. Agora loga em product_events pra alertar caso
      // similar recorra.
      await emitEdu(opts, 'edu_comment.curated_error', {
        error: String(err instanceof Error ? err.message : err).slice(0, 200),
      })
    }
  }

  const userPayload = formatUserPayload(input)
  const startedAt = Date.now()

  // haiku_started é fire-and-forget — ele é PRE-trabalho útil; awaitar adiciona
  // ~80-150ms de RTT ao Supabase antes do Haiku começar, latência sentida pelo
  // paciente. emitEdu já é never-throw internamente.
  void emitEdu(opts, 'edu_comment.haiku_started', { model, kind: input.kind })
  let timer: ReturnType<typeof setTimeout> | undefined
  try {
    const llmPromise = llm.complete({
      model,
      systemPrompt: SYSTEM_PROMPT,
      messages: [{ role: 'user', content: userPayload }],
      temperature: 0.6,
      maxTokens: 300,
      metadata: { Stage: 'edu-comment' },
    })
    // Defesa contra unhandledRejection: o openrouter SDK não recebe AbortSignal
    // hoje, então quando o timeout ganha o race, o llmPromise continua pendente
    // e pode rejeitar mais tarde (timeout interno 90s, 5xx). Sem .catch attach
    // o Node sinaliza unhandledRejection. Silencia defensivamente.
    llmPromise.catch(() => {})
    const timeoutPromise = new Promise<null>((resolve) => {
      timer = setTimeout(() => resolve(null), timeoutMs)
    })
    const result = await Promise.race([llmPromise, timeoutPromise])
    // Limpa o timer SE o llmPromise resolveu primeiro — evita timer pendente
    // mantendo o event loop ativo após o step.run retornar.
    if (timer) clearTimeout(timer)
    if (result === null) {
      await emitEdu(opts, 'edu_comment.haiku_timeout', {
        timeoutMs,
        elapsedMs: Date.now() - startedAt,
      })
      return ''
    }
    const content = (result.content ?? '').trim()
    const cleaned = content.replace(/^\s*```[\s\S]*?```\s*/g, '').trim()
    if (!cleaned) {
      await emitEdu(opts, 'edu_comment.haiku_empty', {
        rawLen: content.length,
        elapsedMs: Date.now() - startedAt,
      })
      return ''
    }
    // Defesa (Roberto 2026-06-09): se o comentário menciona alimento que NÃO
    // está na lista da refeição, drop o comentário inteiro (melhor sem
    // orientação que com orientação inventada). Caso real: café sem manteiga
    // nem óleo recebeu "reduz a manteiga ou óleo" — inventou itens.
    if (input.items && input.items.length > 0 && hasPhantomFoodMention(cleaned, input.items)) {
      await emitEdu(opts, 'edu_comment.phantom_drop', {
        commentPreview: cleaned.slice(0, 160),
        itemNames: input.items.map((i) => i.food_name),
      })
      return ''
    }
    await emitEdu(opts, 'edu_comment.haiku_success', {
      length: cleaned.length,
      elapsedMs: Date.now() - startedAt,
    })
    return cleaned
  } catch (err) {
    if (timer) clearTimeout(timer)
    await emitEdu(opts, 'edu_comment.haiku_error', {
      error: String(err instanceof Error ? err.message : err).slice(0, 200),
      elapsedMs: Date.now() - startedAt,
    })
    return ''
  }
}

/**
 * Detecta menção a alimento "fantasma" — palavras-chave de comida (manteiga,
 * óleo, açúcar, bacon, etc) que NÃO aparecem na lista de items registrados.
 * Conservador: só flag quando há menção EXPLÍCITA com sugestão ("reduz a
 * manteiga", "menos óleo") — não pega menções abstratas.
 */
export function hasPhantomFoodMention(
  comment: string,
  items: Array<{ food_name: string }>,
): boolean {
  const lc = comment.toLowerCase()
  const listedNames = items.map((i) => i.food_name.toLowerCase()).join(' ')
  // Top alimentos comuns que aparecem como sugestão genérica
  const phantomCandidates = [
    'manteiga', 'azeite', 'óleo', 'oleo', 'maionese', 'bacon', 'açúcar', 'acucar',
    'mel', 'creme de leite', 'requeijão', 'requeijao', 'queijo amarelo',
  ]
  // Só flag se: aparece na sugestão (com verbo de orientação) E não está na lista
  const orientationVerb = /(reduz|diminui|corta|tira|substitui|troca|menos)/
  for (const phantom of phantomCandidates) {
    if (lc.includes(phantom) && !listedNames.includes(phantom)) {
      // Checa se está em contexto de sugestão
      const idx = lc.indexOf(phantom)
      const before = lc.slice(Math.max(0, idx - 50), idx)
      if (orientationVerb.test(before)) return true
    }
  }
  return false
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
