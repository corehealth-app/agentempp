/**
 * Golden test harness (Sprint 2.0).
 *
 * Objetivo: dada uma fixture (conversa simulada + estado de banco),
 * rodar o pipeline com um LLM mockado e capturar:
 *   - tools chamadas + args (normalizados)
 *   - texto final (normalizado: números do card removidos via regex,
 *     porque o card é canônico do banco e varia legitimamente)
 *
 * Uso: antes de podar uma agent_rule ou mexer no system prompt, salve um
 * snapshot baseline (`SNAPSHOT_UPDATE=1 pnpm test golden`), faça a mudança,
 * rode de novo. Se tools/args mudaram OU o esqueleto da prosa mudou →
 * regressão. Se só prosa variou (palavras), passa.
 *
 * Este arquivo é o framework; fixtures concretas ficam em
 * __golden__/fixtures/*.ts. A primeira fixture é stub — adicionar fixtures
 * reais é o trabalho de Sprint 2.1 (poda gated por este harness).
 */
import type { OpenRouterLLM } from '@mpp/providers'

export interface GoldenScriptedTurn {
  /** Texto que o LLM "responderá" neste turno. Pode conter tool_calls. */
  llm_response: string
  /** Tool calls que o LLM emite (mocking). Vazio = só prosa. */
  tool_calls?: Array<{ name: string; args: Record<string, unknown> }>
}

export interface GoldenFixture {
  name: string
  description: string
  /** Mensagem do paciente que dispara o turno. */
  user_message: string
  /** Roteiro de respostas do LLM (1 entrada = 1 chamada llm.complete). */
  llm_turns: GoldenScriptedTurn[]
  /** Esperado: lista de tools chamadas no turno. */
  expected_tools_called: string[]
  /** Esperado: presença de tokens-chave no texto final (não exato — palavras
   * canônicas do card/método). Cada item == regex substring. */
  expected_text_contains: string[]
}

/**
 * Cria um mock de OpenRouterLLM que retorna respostas scriptadas em ordem.
 * Cada chamada `complete()` consome o próximo turno do roteiro.
 */
export function buildScriptedLLM(turns: GoldenScriptedTurn[]): OpenRouterLLM {
  let idx = 0
  return {
    complete: async () => {
      const t = turns[idx] ?? turns[turns.length - 1]
      idx += 1
      return {
        content: t?.llm_response ?? '',
        model: 'golden-mock',
        stop_reason: 'end_turn',
      }
    },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any
}

/**
 * Normaliza texto pra comparação golden: remove números (`123` → `N`),
 * remove emojis, colapsa espaços. Foco: comportamento, não prosa exata.
 */
export function normalizeForGolden(text: string): string {
  return text
    .replace(/\b\d+(?:[.,]\d+)?\b/g, 'N')
    .replace(/[🔥💪📊🎯✅⚠️❌]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
}

/**
 * Compara resultado de uma execução com fixture esperada. Retorna lista de
 * diferenças (vazio = match). Use em test files com expect(diffs).toEqual([]).
 */
export interface GoldenRunResult {
  tools_called: string[]
  final_text: string
}

export function diffGolden(
  fixture: GoldenFixture,
  result: GoldenRunResult,
): string[] {
  const diffs: string[] = []
  // Compara conjunto de tools (ordem não importa pra esta versão)
  const expectedSet = new Set(fixture.expected_tools_called)
  const actualSet = new Set(result.tools_called)
  for (const t of expectedSet) {
    if (!actualSet.has(t)) diffs.push(`missing tool: ${t}`)
  }
  for (const t of actualSet) {
    if (!expectedSet.has(t)) diffs.push(`unexpected tool: ${t}`)
  }
  // Tokens-chave no texto final
  const normalized = normalizeForGolden(result.final_text)
  for (const re of fixture.expected_text_contains) {
    if (!new RegExp(re, 'i').test(normalized)) {
      diffs.push(`text missing pattern: /${re}/`)
    }
  }
  return diffs
}
