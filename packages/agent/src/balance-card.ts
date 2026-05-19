/**
 * Card de balanço pré-renderizado pelo sistema (sessão 2026-05-18).
 *
 * Motivação: LLM (mesmo Opus 4.7) inventou "1.376 + 559 = 1.935 kcal excedente"
 * pra Roberto quando ele questionou um número. Validator pegou mas só logou.
 * Regras textuais inviolávies foram ignoradas pelo LLM em modo "explicar erro".
 *
 * Solução estrutural: card de balanço (linhas "🔥 Consumido", "🎯 Restam",
 * "💪 Proteína", "🏃🏻 Exercício", "📊 Bloco 7700") é renderizado pelo SISTEMA
 * com dados determinísticos do banco. LLM NUNCA escreve esses números.
 *
 * Pipeline detecta quando precisa de card (tool registra_refeicao/registra_treino
 * foi chamada com sucesso) e:
 *   - Remove o card alucinado do LLM (regex match das linhas)
 *   - Anexa o card pré-renderizado real
 *
 * LLM continua livre pra escrever preâmbulo + tabela de itens da refeição +
 * comentário motivacional. SÓ o card de balanço é cativo do sistema.
 */

export interface BalanceCardData {
  /** Consumido hoje (kcal). */
  caloriesConsumed: number
  /** Meta calórica do dia. */
  caloriesTarget: number | null
  /** Proteína consumida (g). */
  proteinG: number
  /** Meta de proteína (g). */
  proteinTarget: number | null
  /** Exercício queimado hoje (kcal). */
  exerciseCalories: number
  /** Bloco 7700 atual em kcal (deficit_block do user_progress). */
  deficitBlock: number
  /** Protocolo do paciente — afeta linha do bloco/orçamento (recomp tem bloco
   * 7700, manutenção/ganho tem orçamento 14d). */
  protocol?: 'recomposicao' | 'ganho_massa' | 'manutencao' | null
  /** Janela 14d (manutenção/ganho_massa). */
  last14d?: { consumed_total: number; target_total: number; dam: number; days_with_data: number } | null
}

const PT_NUM = new Intl.NumberFormat('pt-BR')

function fmt(n: number): string {
  return PT_NUM.format(Math.round(n))
}

function pct(num: number, den: number): number {
  if (!den || den <= 0) return 0
  return Math.round((num / den) * 100)
}

/**
 * Renderiza o card de balanço no formato canônico MPP.
 * Esse formato é a "verdade visual" do sistema — NÃO mudar sem migrar todos
 * os agent_rules que ensinam o LLM.
 */
export function renderBalanceCard(data: BalanceCardData): string {
  const lines: string[] = []

  // Linha 1: 🔥 Consumido com fração
  if (data.caloriesTarget != null && data.caloriesTarget > 0) {
    const p = pct(data.caloriesConsumed, data.caloriesTarget)
    lines.push(`🔥 Consumido: **${fmt(data.caloriesConsumed)} / ${fmt(data.caloriesTarget)} kcal (${p}%)**`)
  } else {
    lines.push(`🔥 Consumido: **${fmt(data.caloriesConsumed)} kcal**`)
  }

  // Linha 2: 🎯 Restam OU Excedente
  if (data.caloriesTarget != null && data.caloriesTarget > 0) {
    const diff = data.caloriesConsumed - data.caloriesTarget
    if (diff > 0) {
      lines.push(`🎯 Excedente: **${fmt(diff)} kcal**`)
    } else {
      lines.push(`🎯 Restam: **${fmt(-diff)} kcal**`)
    }
  }

  // Linha 3: 💪 Proteína
  if (data.proteinTarget != null && data.proteinTarget > 0) {
    const p = pct(data.proteinG, data.proteinTarget)
    const proteinDisplay = Number.isInteger(data.proteinG)
      ? String(data.proteinG)
      : data.proteinG.toFixed(1)
    lines.push(`💪 Proteína: **${proteinDisplay} / ${fmt(data.proteinTarget)}g (${p}%)**`)
  } else {
    lines.push(`💪 Proteína: **${data.proteinG.toFixed(1)}g**`)
  }

  // Linha 4: 🏃🏻 Exercício (sempre mostra, mesmo se 0)
  lines.push(`🏃🏻 Exercício: **${fmt(data.exerciseCalories)} kcal**`)

  // Linha 5: 📊 Bloco 7700 (recomp) OU Orçamento 14d (outros protocolos)
  if (data.protocol === 'recomposicao') {
    const p = pct(data.deficitBlock, 7700)
    lines.push(`📊 Bloco 7700: **${fmt(data.deficitBlock)} / 7.700 kcal (${p}%)**`)
  } else if (data.last14d && data.last14d.target_total > 0) {
    const l = data.last14d
    const p = pct(l.consumed_total, l.target_total)
    lines.push(
      `📊 Orçamento 14d: **${fmt(l.consumed_total)} / ${fmt(l.target_total)} kcal (${p}%)** · DAM: ${l.dam}/${l.days_with_data}`,
    )
  }

  return lines.join('\n')
}

/**
 * Detecta se um texto contém um card de balanço alucinado pelo LLM.
 * Usado pelo pipeline pra REMOVER o card do LLM e SUBSTITUIR pelo
 * pré-renderizado. Regex match nas linhas começando com emojis canônicos.
 */
const CARD_LINE_RE =
  /^(?:🔥\s*Consumido|🎯\s*(?:Restam|Excedente)|💪\s*Prote[íi]na|🏃🏻\s*Exerc[íi]cio|📊\s*(?:Bloco\s*7700|Or[çc]amento\s*14d))[^\n]*$/gmu

export function stripBalanceCard(text: string): string {
  // Remove linhas do card. Mantém o resto (preâmbulo + tabela de items +
  // comentário motivacional). Limpa linhas em branco extras resultantes.
  return text
    .replace(CARD_LINE_RE, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
}

export function hasBalanceCard(text: string): boolean {
  return /🔥\s*Consumido[^\n]*kcal/u.test(text)
}

/**
 * Substitui o card alucinado pelo card pré-renderizado.
 * Se o texto NÃO tinha card, anexa no final (separado por linha em branco).
 */
export function injectCanonicalCard(text: string, card: string): string {
  if (hasBalanceCard(text)) {
    const stripped = stripBalanceCard(text)
    return `${stripped}\n\n${card}`.trim()
  }
  return `${text.trim()}\n\n${card}`.trim()
}
