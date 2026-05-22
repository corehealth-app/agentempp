/**
 * LLM-as-Judge — avalia a qualidade das respostas do agente MPP.
 * Usado pelo cron `sample-judge` (amostra ~10% das respostas) pra popular a
 * tabela `llm_evaluations` e a tela /evaluations do admin (detecta regressão
 * após mudança de prompt).
 *
 * Aqui ficam só as partes PURAS (rubrica + parser); a chamada ao LLM e o I/O
 * ficam no worker. Critérios refletem o que mais importa nesse agente (e o que
 * a gente passou a sessão consertando): número correto, sem alucinar registro,
 * tom MPP, português.
 */

export interface JudgePrompt {
  system: string
  user: string
}

export function buildJudgePrompt(input: {
  userInput: string
  agentResponse: string
  stage: string | null
}): JudgePrompt {
  const system =
    'Você é um AVALIADOR (LLM-as-judge) das respostas de um agente de coaching ' +
    'nutricional por WhatsApp (Método MPP, Dr. Roberto Menescal). Dê uma nota de ' +
    '*0 a 10* para a RESPOSTA DO AGENTE, considerando:\n' +
    '- Correção: números coerentes, sem inventar (kcal, proteína, déficit, bloco).\n' +
    '- Método MPP: não confunde balanço de comida com déficit real; exercício acelera o bloco, não libera comer mais.\n' +
    '- Não afirma ter registrado/corrigido sem de fato fazer.\n' +
    '- Tom acolhedor, claro, em português do Brasil; sem jargão em inglês.\n' +
    '- Pertinência: responde o que o paciente disse.\n' +
    'Responda APENAS um JSON: {"score": <0-10>, "reasoning": "<1-2 frases curtas em PT-BR>"}.'
  const user =
    `Stage: ${input.stage ?? 'desconhecido'}\n\n` +
    `Mensagem do paciente:\n"""${input.userInput || '(sem texto / proativa)'}"""\n\n` +
    `Resposta do agente (avaliar esta):\n"""${input.agentResponse}"""`
  return { system, user }
}

export interface JudgeResult {
  score: number
  reasoning: string
}

/** Extrai {score, reasoning} do texto do LLM. Tolera code fence. Clampa 0-10. */
export function parseJudgeResult(text: string): JudgeResult | null {
  if (!text) return null
  const m = text.match(/\{[\s\S]*\}/)
  if (!m) return null
  let obj: unknown
  try {
    obj = JSON.parse(m[0])
  } catch {
    return null
  }
  const o = obj as { score?: unknown; reasoning?: unknown }
  if (typeof o.score !== 'number' || !Number.isFinite(o.score)) return null
  const score = Math.max(0, Math.min(10, Math.round(o.score)))
  const reasoning = typeof o.reasoning === 'string' ? o.reasoning : ''
  return { score, reasoning }
}
