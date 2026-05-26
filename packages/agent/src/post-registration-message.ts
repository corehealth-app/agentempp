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

export type { BalanceCardData }
