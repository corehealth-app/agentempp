/**
 * Detector de resposta TEXTUAL ao botão de pending (Fase B/D — DEC-3 do plano
 * em /root/.claude/plans/botoes-whatsapp.md).
 *
 * Paciente que digita "sim" / "tá" / "ok" em vez de tocar o botão → tratamos
 * como tap em [Sim, registrar]. "não" / "editar" → tap em [Editar]. Qualquer
 * outra coisa = msg normal (cai no fluxo do LLM); o cancelamento do pending
 * antigo já é feito no pipeline quando a nova msg dispara registra_refeicao
 * /registra_treino.
 *
 * Conservador: só faz match em texto CURTO e com padrão claro. Texto longo
 * (ex: "sim, comi também 100g de arroz") NÃO bate — a intenção é registrar
 * algo novo, não confirmar o pending.
 */

// Confirmações simples
const CONFIRM_PATTERN =
  /^\s*(s|sim|s[ií]|t[áa]|ok|isso|isso\s+mesmo|confirma|confirmo|registra|pode\s+registrar|positivo|👍|✅|👌)\s*[.!]?\s*$/i

// Pedido de correção
const EDIT_PATTERN =
  /^\s*(n[aã]o|nao|editar|edita|corrige|corrija|errado|errou|t[áa]\s+errado|n[aã]o\s+é\s+(isso|esse)|errei|deixa\s+pra\s+l[áa])\s*[.!]?\s*$/i

const MAX_LEN = 30 // texto curto: confirmações reais são <30 chars

export function detectPendingResponse(text: string | null | undefined): 'confirm' | 'edit' | null {
  if (!text) return null
  const t = text.trim()
  if (t.length === 0 || t.length > MAX_LEN) return null
  if (CONFIRM_PATTERN.test(t)) return 'confirm'
  if (EDIT_PATTERN.test(t)) return 'edit'
  return null
}
