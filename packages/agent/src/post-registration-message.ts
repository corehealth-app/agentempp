/**
 * Mensagem de registro montada pelo SISTEMA (Roberto 2026-05-25).
 *
 * Quando o turno é um REGISTRO PURO (paciente mandou comida/treino, sem pergunta),
 * o sistema compõe a resposta inteira — confirmação curta + tabela de itens +
 * card de balanço canônico — SEM a 2ª chamada do LLM. Mata a imprecisão (a IA
 * às vezes errava/variava o número) e economiza uma chamada por registro.
 *
 * Os números do card vêm de `renderBalanceCard` (mesma fonte canônica do FIX C);
 * a tabela vem do retorno determinístico de `registra_refeicao`. Coaching/
 * conversa continua com a IA nos demais turnos (e nas mensagens de engajamento).
 */
import { renderBalanceCard, type BalanceCardData } from './balance-card.js'

const PT_NUM = new Intl.NumberFormat('pt-BR')
const fmt = (n: number): string => PT_NUM.format(Math.round(n))
/** Macro em g: inteiro quando exato, senão 1 casa (ex: "2", "0.5"). */
const gram = (n: number): string => (Number.isInteger(n) ? String(n) : n.toFixed(1))

const MEAL_LABEL: Record<string, string> = {
  cafe: 'Café',
  almoco: 'Almoço',
  lanche: 'Lanche',
  jantar: 'Jantar',
  ceia: 'Ceia',
  outro: 'Refeição',
}
/** Frase fixa de confirmação por tipo (decisão Eduardo: uma frase só, sem pool). */
const MEAL_CONFIRM: Record<string, string> = {
  cafe: 'Café registrado ✅',
  almoco: 'Almoço registrado ✅',
  lanche: 'Lanche registrado ✅',
  jantar: 'Jantar registrado ✅',
  ceia: 'Ceia registrada ✅',
  outro: 'Refeição registrada ✅',
}

export interface MealItem {
  name: string
  quantity_g: number
  display_qty?: number | null
  display_unit?: string | null
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
}
export interface MealTotals {
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
}

/** Quantidade exibida: unidade natural quando houver ("2 unidades", "250 ml"),
 * senão gramas ("200g"). */
function displayQty(it: MealItem): string {
  const unit = (it.display_unit ?? 'g').trim()
  const qty = it.display_qty ?? it.quantity_g
  if (unit === 'g' || unit === 'gramas' || unit === '') return `${fmt(qty)}g`
  return `${qty} ${unit}`
}

/**
 * Tabela de itens da refeição no formato canônico MPP (sempre os 4 macros, na
 * ordem kcal | proteína | carboidrato | gordura — regra inviolável do manual).
 */
export function formatMealTable(
  mealType: string | null | undefined,
  items: MealItem[],
  totals: MealTotals,
): string {
  const label = MEAL_LABEL[mealType ?? 'outro'] ?? MEAL_LABEL.outro
  const lines: string[] = [`**${label}:**`]
  for (const it of items) {
    lines.push(
      `• *${it.name} (${displayQty(it)}):* ${fmt(it.kcal)} kcal | ${gram(it.protein_g)}g proteína | ${gram(it.carbs_g)}g carboidrato | ${gram(it.fat_g)}g gordura`,
    )
  }
  lines.push('')
  lines.push(
    `**Total: ${fmt(totals.kcal)} kcal | ${gram(totals.protein_g)}g proteína | ${gram(totals.carbs_g)}g carboidrato | ${gram(totals.fat_g)}g gordura**`,
  )
  return lines.join('\n')
}

export interface RegistrationEntry {
  tool: 'registra_refeicao' | 'registra_treino'
  /** refeição */
  mealType?: string | null
  items?: MealItem[]
  totals?: MealTotals
  /** dedup: todos os itens já existiam hoje (Fix A) → sem tabela */
  alreadyLogged?: boolean
  /** treino */
  workoutType?: string | null
  durationMin?: number | null
  kcalBurned?: number | null
}

const REG_TOOLS = ['registra_refeicao', 'registra_treino']

/**
 * Decide se o turno é um REGISTRO PURO que pode ser respondido pelo sistema
 * (sem 2ª chamada do LLM). Gatilho conservador (não perder performance):
 *  - todas as tools do turno foram registra_refeicao/registra_treino, com sucesso;
 *  - o paciente NÃO fez pergunta (sem "?") — se fez, o LLM responde (fallback).
 */
export function isPureRegistrationTurn(
  entries: Array<{ name: string; error?: unknown; result?: unknown }>,
  patientText: string | null | undefined,
): boolean {
  if (entries.length === 0) return false
  const allRegistration = entries.every(
    (e) => REG_TOOLS.includes(e.name) && !e.error && !!e.result,
  )
  if (!allRegistration) return false
  if (/\?/.test(patientText ?? '')) return false
  // Review HIGH 3 (audit 06-24 review): excluir entries do Layer 1 suppression.
  // Quando pipeline.ts:701 marca `result.suppressed_as_duplicate=true`, a tool
  // NÃO foi executada — paciente continua aguardando confirmação do pending
  // anterior. Cair em composePostRegistrationMessage chamaria Haiku edu-comment
  // desnecessariamente (custo + latência) e, pior, geraria texto "Refeição
  // registrada ✅" que poderia contradizer o botão "Confirma?" do M3 se algum
  // caller usar `result.text`.
  if (
    entries.some(
      (e) => (e.result as { suppressed_as_duplicate?: boolean } | null)?.suppressed_as_duplicate === true,
    )
  ) {
    return false
  }
  return true
}

export interface PostRegistrationInput {
  /** registros do turno (normalmente 1; pode ter refeição + treino juntos) */
  registrations: RegistrationEntry[]
  /** dados frescos do banco pro card canônico (mesma fonte do FIX C) */
  card: BalanceCardData
}

/**
 * Compõe a mensagem inteira de um turno de registro, sem LLM:
 *   frase fixa + tabela(s)/resumo de treino + card de balanço canônico.
 */
export function composePostRegistrationMessage(input: PostRegistrationInput): string {
  const blocks: string[] = []
  for (const reg of input.registrations) {
    if (reg.tool === 'registra_treino') {
      if (reg.alreadyLogged) {
        blocks.push('Treino registrado ✅\n\n_(já estava registrado)_')
        continue
      }
      const dur = reg.durationMin ? ` (${reg.durationMin} min)` : ''
      const wt = reg.workoutType ?? 'Treino'
      blocks.push(`Treino registrado ✅\n\n🏋️ ${wt}${dur} — ${fmt(reg.kcalBurned ?? 0)} kcal`)
      continue
    }
    const confirm = MEAL_CONFIRM[reg.mealType ?? 'outro'] ?? MEAL_CONFIRM.outro
    if (reg.alreadyLogged || !reg.items || reg.items.length === 0) {
      blocks.push(`${confirm}\n\n_(já estava registrado)_`)
    } else {
      blocks.push(
        `${confirm}\n\n${formatMealTable(reg.mealType, reg.items, reg.totals ?? { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 })}`,
      )
    }
  }
  const card = renderBalanceCard(input.card)
  return `${blocks.join('\n\n')}\n\n${card}`
}

/**
 * Split a mensagem de registro em 2 partes pra envio fragmentado: confirmação
 * + tabela da refeição/treino (parte 1) e card de balanço diário (parte 2).
 * Critério: o card de balanço SEMPRE começa com "🔥 Consumido:" (renderBalanceCard).
 * Se o marker não existir (mensagem que não é registro), devolve a string toda
 * como `meal` e `card=null` — caller manda só uma msg.
 *
 * Roberto 2026-05-30: msg consolidada estava muito densa (5 itens + total +
 * card num único bloco). Dividir deixa o paciente ler em 2 etapas naturais
 * sem perder informação.
 */
export function splitMealAndCard(text: string): { meal: string; card: string | null } {
  const markerIdx = text.indexOf('🔥 Consumido:')
  if (markerIdx === -1) return { meal: text, card: null }
  const meal = text.slice(0, markerIdx).trimEnd()
  const card = text.slice(markerIdx).trimStart()
  if (!meal || !card) return { meal: text, card: null }
  return { meal, card }
}

/**
 * Roberto 2026-06-01: marker invisível usado pra delimitar o comentário
 * educativo, permitindo splitar em 3 bolhas (tabela | comentário | card).
 * Zero-width space (U+200B) é renderizado como nada no WhatsApp mas sobrevive
 * aos validators de pipeline (que mexem em texto/números, não em whitespace).
 */
export const EDU_COMMENT_MARKER = '​​​'

/**
 * Insere o comentário educativo entre tabela e card, marcado com
 * EDU_COMMENT_MARKER (zero-width tripla) pra splitRegistrationParts dividir
 * em 3 bolhas.
 *
 * **Invariante** (travado por tool-items-adapter.test.ts):
 *   eduComment não-vazio  ⇒  string retornada contém EDU_COMMENT_MARKER
 *   eduComment vazio/null ⇒  string retornada === finalText (sem mudança)
 *
 * Antes era código inline em pipeline.ts:920 e interactive-handler.ts:466.
 * Extraído em função pura testável depois do audit 2026-06-14: 52% dos
 * registros saíam sem comentário em prod, e não havia teste garantindo
 * que QUANDO comentário existe, ele entra entre tabela e card.
 */
export function embedEduComment(finalText: string, eduComment: string | null | undefined): string {
  if (!eduComment) return finalText
  const { meal, card } = splitMealAndCard(finalText)
  if (card) {
    return `${meal}\n\n${EDU_COMMENT_MARKER}${eduComment}\n\n${card}`
  }
  // Sem card detectado (mensagem de erro ou registro sem balanço): grava
  // comentário no final, ainda marcado pra split poder isolar a bolha.
  return `${finalText}\n\n${EDU_COMMENT_MARKER}${eduComment}`
}

/**
 * Split em 3 partes — tabela do registro, comentário educativo, card de
 * balanço. Marker do comentário é EDU_COMMENT_MARKER (zero-width tripla),
 * inserido pelo pipeline/handler antes de concatenar o comentário. Se não
 * houver marker, devolve só meal+card (igual splitMealAndCard).
 */
export function splitRegistrationParts(text: string): {
  meal: string
  comment: string | null
  card: string | null
} {
  const { meal: mealCard, card } = splitMealAndCard(text)
  const idx = mealCard.indexOf(EDU_COMMENT_MARKER)
  if (idx === -1) return { meal: mealCard, comment: null, card }
  const meal = mealCard.slice(0, idx).trimEnd()
  const comment = mealCard.slice(idx + EDU_COMMENT_MARKER.length).trimStart()
  if (!meal || !comment) return { meal: mealCard, comment: null, card }
  return { meal, comment, card }
}

// ── #1 STATUS SOB DEMANDA (Roberto 2026-05-27) ──────────────────────────────
// "como tô / quanto falta / meu bloco" → o sistema responde com o card canônico
// (mesma fonte do registro), sem a 2ª chamada do LLM. Gatilho conservador: só
// quando a única tool foi consulta_progresso E a msg é status PURO (sem coaching/
// pergunta extra). Qualquer pergunta de coaching junto → fallback pro LLM.

const STATUS_TOOLS = ['consulta_progresso']
// Trailing `(?![\p{L}])` em vez de `\b`: `\b` usa só [A-Za-z0-9_] e FALHA depois de
// letra acentuada (ex: "tô" termina em "ô"). O lookahead Unicode resolve e ainda
// evita falso-positivo "como tomate" (não-status) ao exigir não-letra após "tô".
/** Intenção de status puro do paciente. */
const STATUS_INTENT =
  /\b(como\s+(t[oô]|estou|vou|t[aá]\s+(meu|o)\s+dia|t[aá]\s+indo)|quanto\s+(falta|me\s+resta|sobra|tenho)|meu\s+bloco|status\s+do\s+dia|resumo\s+do\s+dia|como\s+est[aá]\s+(meu\s+dia|o\s+dia))(?![\p{L}])/iu
/** Marcadores de coaching/decisão/pergunta extra → NÃO é status puro (generoso = mais fallback). */
const STATUS_COACHING_MARKER =
  /\b(posso|consigo|devo|pode|por\s*qu[eê]|porqu[eê]|o\s+que|qual|quais|como\s+fa[çc]o|recomenda|sugest|acha|vale\s+a\s+pena|melhor|troc|substitu|jantar|almo[çc]ar|comer|treinar)/i

/**
 * Decide se o turno é uma CONSULTA DE STATUS PURA que o sistema pode responder
 * (sem 2ª chamada do LLM). Conservador:
 *  - todas as tools do turno = consulta_progresso, com sucesso;
 *  - a msg do paciente tem intenção de status E não tem marcador de coaching.
 */
export function isPureStatusQueryTurn(
  entries: Array<{ name: string; error?: unknown; result?: unknown }>,
  patientText: string | null | undefined,
): boolean {
  if (entries.length === 0) return false
  const allStatus = entries.every((e) => STATUS_TOOLS.includes(e.name) && !e.error && !!e.result)
  if (!allStatus) return false
  const text = patientText ?? ''
  if (!STATUS_INTENT.test(text)) return false
  if (STATUS_COACHING_MARKER.test(text)) return false
  return true
}

export interface StatusProgress {
  currentStreak: number
  level: number
  xpTotal: number
  blocksCompleted: number
}

/**
 * Compõe a resposta de status, sem LLM: card de balanço canônico + 1 linha de
 * progresso (sequência/nível/blocos). Mesmos números do registro/engajamento.
 */
export function composeStatusMessage(card: BalanceCardData, progress: StatusProgress): string {
  const c = renderBalanceCard(card)
  const seq =
    progress.currentStreak === 1 ? '1 dia consecutivo' : `${progress.currentStreak} dias consecutivos`
  const line = `🏅 Sequência: **${seq}** · Nível ${progress.level} (${fmt(progress.xpTotal)} XP) · ${progress.blocksCompleted} bloco(s) de 7.700 completo(s)`
  return `${c}\n\n${line}`
}

// ── #2 RESULTADO DE REAVALIAÇÃO (Roberto 2026-05-27) ────────────────────────
// Quando o paciente responde a reavaliação (peso/fotos/fome), o sistema confirma
// a NOVA meta (os números que valem os próximos 14 dias) de forma determinística,
// em vez de a IA re-redigir. Gatilho ESTREITO (no pipeline): só em reavaliação
// real (stage de protocolo ativo + reevaluation.due recente), nunca no onboarding.

const REEVAL_TOOLS = ['cadastra_dados_iniciais', 'define_protocolo']
const PROTOCOL_LABEL: Record<string, string> = {
  recomposicao: 'Recomposição corporal',
  ganho_massa: 'Ganho de massa muscular',
  manutencao: 'Manutenção',
}

/**
 * Parte barata do gatilho de reavaliação (checa só as tools do turno):
 *  - todas as tools = cadastra_dados_iniciais/define_protocolo, com sucesso;
 *  - há ao menos um cadastra_dados_iniciais (o peso — sinal canônico da reavaliação);
 *  - o paciente não fez pergunta (sem "?").
 * A confirmação de que É reavaliação (não onboarding/update casual) fica no
 * pipeline (stage ativo + reevaluation.due recente).
 */
export function isReevalToolTurn(
  entries: Array<{ name: string; error?: unknown; result?: unknown }>,
  patientText: string | null | undefined,
): boolean {
  if (entries.length === 0) return false
  const allReeval = entries.every(
    (e) => REEVAL_TOOLS.includes(e.name) && !e.error && !!e.result,
  )
  const hasCadastra = entries.some((e) => e.name === 'cadastra_dados_iniciais')
  if (!allReeval || !hasCadastra) return false
  if (/\?/.test(patientText ?? '')) return false
  return true
}

export interface ReevalResult {
  caloriesTarget: number | null
  proteinTarget: number | null
  protocol: string | null
}

/** Mensagem determinística de fim de reavaliação: confirma a nova meta + próxima em 14d. */
export function composeReevalResultMessage(r: ReevalResult): string {
  const lines = ['Reavaliação concluída ✅', '']
  if (r.caloriesTarget != null && r.proteinTarget != null) {
    lines.push(
      `🎯 Nova meta: **${fmt(r.caloriesTarget)} kcal** | **${gram(Number(r.proteinTarget))} g** de proteína`,
    )
  } else if (r.caloriesTarget != null) {
    lines.push(`🎯 Nova meta: **${fmt(r.caloriesTarget)} kcal**`)
  }
  if (r.protocol) lines.push(`📋 Protocolo: ${PROTOCOL_LABEL[r.protocol] ?? r.protocol}`)
  lines.push('')
  lines.push('Próxima reavaliação em 14 dias. Seguimos! 💪')
  return lines.join('\n')
}

// ── PENDING PROPOSAL: BOTÕES [Sim, registrar] / [Editar] (Roberto 2026-05-28) ──
// Compõe a mensagem que o agente envia ao paciente pra ele CONFIRMAR antes de gravar.
// Não chama a tool de gravar — só propõe. A gravação real só acontece quando o
// paciente toca [Sim, registrar] (handler determinístico em interactive-handler.ts).
// Resolve a classe `llm.fake_write_detected`: a gravação vira do TAP, não da decisão
// do LLM. Plano completo: /root/.claude/plans/botoes-whatsapp.md (opção #4, Fase A).
//
// Limite Meta: body 1024 chars, title 20 chars. A função enforca limites realistas
// (refeição até 10 items cabe folgado; treino é uma linha só).

export interface PendingProposal {
  kind: 'meal' | 'workout'
  mealType?: string
  items?: MealItem[]
  totals?: MealTotals
  workoutType?: string
  durationMin?: number | null
  kcalEst?: number | null
  /** Tipo da mensagem que originou a proposta (Roberto 2026-05-28). Varia o
   * texto da abertura: foto → "Vi isso na sua foto"; áudio → "Entendi do áudio";
   * texto default → "Entendi isso pro seu ...". */
  sourceContentType?: 'text' | 'image' | 'audio' | null
}

export interface PendingProposalMessage {
  body: string
  buttons: Array<{ id: string; title: string }>
}

/** Compõe o corpo (texto) + os 2 botões pra mensagem interactive da proposta. */
export function composePendingProposal(
  pendingId: string,
  proposal: PendingProposal,
): PendingProposalMessage {
  const buttons = [
    { id: `confirm_${pendingId}`, title: 'Sim, registrar' },
    { id: `edit_${pendingId}`, title: 'Editar' },
  ]

  // Abertura varia por tipo de origem (foto/áudio/texto) — Roberto 2026-05-28
  const sourceOpening = (label: string): string => {
    if (proposal.sourceContentType === 'image') return `Vi isso na sua foto (${label}):`
    if (proposal.sourceContentType === 'audio') return `Entendi isso do áudio (${label}):`
    return `Entendi isso pro seu ${label}:`
  }

  if (proposal.kind === 'workout') {
    const wt = proposal.workoutType ?? 'treino'
    const dur = proposal.durationMin ? ` (${proposal.durationMin} min)` : ''
    const kcal = proposal.kcalEst != null ? ` — ${fmt(proposal.kcalEst)} kcal` : ''
    return {
      body: `${sourceOpening('treino')}\n\n🏋️ ${wt}${dur}${kcal}\n\nConfirma?`,
      buttons,
    }
  }

  // meal
  const label = MEAL_LABEL[proposal.mealType ?? 'outro'] ?? MEAL_LABEL.outro ?? 'Refeição'
  const items = proposal.items ?? []
  const lines = [sourceOpening(label), '']
  for (const it of items) {
    lines.push(`• ${it.name} (${displayQty(it)}) — ${fmt(it.kcal)} kcal`)
  }
  if (proposal.totals) {
    const t = proposal.totals
    lines.push('')
    lines.push(
      `Total: ${fmt(t.kcal)} kcal | ${gram(t.protein_g)}g proteína | ${gram(t.carbs_g)}g carboidrato | ${gram(t.fat_g)}g gordura`,
    )
  }
  lines.push('')
  lines.push('Confirma?')
  let body = lines.join('\n')
  // Salvaguarda hard contra estouro de 1024 chars do Meta (refeição absurda):
  // trunca preservando o "Confirma?" no fim.
  if (body.length > 1024) {
    const tail = '\n…\n\nConfirma?'
    body = body.slice(0, 1024 - tail.length) + tail
  }
  return { body, buttons }
}

export type { BalanceCardData }
