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
import { eatingBalance } from '@mpp/core'

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

  // Linha 2: 🎯 Restam OU Excedente — APENAS comida (meta − consumido).
  // REGRA MPP (Roberto 2026-05-21): o exercício NÃO entra no "Restam". Queimar
  // no treino acelera a perda (vai pro BLOCO 7700), mas NÃO libera comer mais —
  // "Restam" é só quanto ainda dá pra comer pra bater a META DE INGESTÃO.
  // O exercício aparece na linha 🏃🏻 e é creditado no bloco pelo daily-closer
  // (que usa consumed−target−exercise — esse cálculo do BLOCO NÃO muda).
  // ⚠️ Reverte o ajuste de 2026-05-19 que somava exercício aqui (inflava o
  //    "Restam" quando abaixo da meta). Ver docs/CALCULO-MPP.md (regra do card).
  if (data.caloriesTarget != null && data.caloriesTarget > 0) {
    const eb = eatingBalance(data.caloriesConsumed, data.caloriesTarget)
    if (eb > 0) {
      lines.push(`🎯 Excedente: **${fmt(eb)} kcal**`)
    } else {
      lines.push(`🎯 Restam: **${fmt(-eb)} kcal**`)
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

  // Linha 4: 🏃🏻 Exercício (sempre mostra, mesmo se 0). Na recomposição, quando
  // > 0, anota que vai pro bloco — reforça que NÃO libera comer mais (regra MPP,
  // ver linha 2). Em manutenção/ganho não há bloco, então sem anotação.
  if (data.exerciseCalories > 0 && data.protocol === 'recomposicao') {
    lines.push(`🏃🏻 Exercício: **${fmt(data.exerciseCalories)} kcal** _(acelera o bloco 7700)_`)
  } else {
    lines.push(`🏃🏻 Exercício: **${fmt(data.exerciseCalories)} kcal**`)
  }

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

/**
 * Substitui MENÇÕES SOLTAS de Bloco 7700 em texto livre (fora do card).
 *
 * Caso real Roberto 2026-05-18: além de mostrar "3.000 / 7.700 kcal" no card
 * (resolvido pelo injectCanonicalCard), LLM podia mencionar "você está em
 * 3.000 do bloco" ou "faltam X kcal pro bloco 7.700" em texto livre. O fix C
 * (card canônico) só pega quando o card completo está presente. Casos soltos
 * passavam batido — validator logava mas não corrigia.
 *
 * Esta função procura padrões soltos e substitui pelo valor real:
 *   - "Bloco 7700: X kcal"
 *   - "X / 7.700 kcal"
 *   - "X kcal de 7.700"
 *   - "X de 7700"
 *   - "Você está em X do bloco"
 *
 * Só substitui se o valor mencionado difere do real em >100 kcal ou >15%.
 * Tolera diferença pequena (LLM arredondou minimamente sem mudar significado).
 */
export function replaceLooseBlockMentions(
  text: string,
  deficitBlock: number,
): { text: string; replacements: number } {
  let result = text
  let count = 0
  const realFmt = PT_NUM.format(deficitBlock)
  const realPct = Math.round((deficitBlock / 7700) * 100)

  // Helper: substitui número claimed pelo real se diferir significativamente
  const shouldReplace = (claimed: number) =>
    Math.abs(claimed - deficitBlock) > 100 && Math.abs(claimed - deficitBlock) / Math.max(deficitBlock, 1) > 0.05

  // Padrão A: "Bloco 7700: **X / 7.700 kcal** (Y%)" ou "Bloco 7700: X kcal de 7700"
  // Captura número + porcentagem opcional. Permite ** envolvendo todo o
  // valor "**X / 7.700 kcal**", "kcal" final opcional, "(Y%)" opcional.
  // [^\d\n]{0,25}? (não-guloso): permite palavras entre "bloco 7700" e o número
  // (ex: "bloco 7700 agora em 2.958..."). Bug Roberto 2026-05-25.
  const patA = /\bbloco\s*7\.?700[^\d\n]{0,25}?\*{0,2}\s*(\d{1,4}(?:[.,]\d{3})?)\s*\*{0,2}\s*(?:kcal\s*)?(?:\/|de|kcal\s*de)\s*\*{0,2}\s*7\.?700(?:\s*kcal)?\s*\*{0,2}(?:\s*\(\s*(\d{1,3})\s*%\s*\))?/gi
  result = result.replace(patA, (full, numStr, pctStr) => {
    const claimed = Number(String(numStr).replace(/\./g, '').replace(',', '.'))
    if (!Number.isFinite(claimed) || !shouldReplace(claimed)) return full
    count++
    return pctStr
      ? `Bloco 7700: **${realFmt} / 7.700 kcal** (${realPct}%)`
      : `Bloco 7700: **${realFmt} / 7.700 kcal**`
  })

  // Padrão B: "X / 7.700" ou "X / 7700" SOLTO (sem prefixo "Bloco" — frase livre)
  // Cuidado: já consumimos o "Bloco 7700: X / 7.700" no patA acima, então o que
  // sobra é menção solta. Match flag /g mantém estado, não repete dentro do mesmo
  // texto após replace.
  // Aceita "/" OU "de" (ex: "2.958 kcal de 7.700"), com "kcal" opcional. Bug Roberto 2026-05-25.
  const patB = /(\d{1,4}(?:[.,]\d{3})?)\s*(?:kcal\s*)?(?:\/|de)\s*7\.?700\b/gi
  result = result.replace(patB, (full, numStr) => {
    const claimed = Number(String(numStr).replace(/\./g, '').replace(',', '.'))
    if (!Number.isFinite(claimed) || !shouldReplace(claimed)) return full
    count++
    return `${realFmt} / 7.700`
  })

  return { text: result, replacements: count }
}

/**
 * Reconcilia QUALQUER menção do bloco 7700 na prosa pelo valor canônico do
 * banco (`user_progress.deficit_block`), com o % recalculado de
 * `round(deficitBlock / 7700 * 100)`.
 *
 * Bug (E) Roberto 2026-05-25: a mensagem matinal de engajamento chama o LLM
 * direto (NÃO passa pelo card canônico do pipeline.ts), então o número do bloco
 * que o LLM escreve não era validado contra o banco — ele ALUCINOU "2.958 / 7.700
 * (38%)" quando o real era 1.235. O número do bloco tem que vir do banco, igual
 * aos outros rótulos determinísticos do engagement-sender (realDailyDeficit etc).
 *
 * Wrapper de assinatura simples sobre `replaceLooseBlockMentions` (que concentra
 * os padrões já endurecidos — "N / 7.700", "N/7700", "bloco 7700 ... N kcal de
 * 7700"). Mantém uma fonte única de regex pra não dar drift no exato caso que
 * este fix existe pra cobrir. Retorna o texto reconciliado; se não há menção de
 * bloco (ou o número já está correto), devolve o texto inalterado — NÃO força o
 * bloco a aparecer.
 *
 * Use `replaceLooseBlockMentions` direto quando precisar do `replacements` pra
 * auditoria/log; este wrapper é o ponto de uso quando só importa o texto final.
 */
export function reconcileBlocoMention(
  text: string,
  { deficitBlock }: { deficitBlock: number },
): string {
  return replaceLooseBlockMentions(text, deficitBlock).text
}
