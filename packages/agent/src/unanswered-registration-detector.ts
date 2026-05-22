/**
 * Detector determinístico de "pedido de registro de refeição" numa mensagem
 * INBOUND do paciente.
 *
 * Backstop da classe de falha "agente ficou MUDO" (caso Erika 2026-05-17: ela
 * pediu 3× "Registre meu almoço: camarão refogado, purê, feijão e farofa" e o
 * agente NUNCA respondeu nem gravou — almoço perdido por SILÊNCIO).
 *
 * Por que o guard fake-write NÃO cobre isso: o `detectFakeWrite` dispara quando
 * o agente AFIRMA ter registrado (texto "salvo/registrado/Total refeição") sem
 * chamar a tool. Aqui não há texto NENHUM do agente — não há o que interceptar
 * no turno. Por isso a detecção é do lado da ENTRADA, e a auditoria (daily-audit)
 * cruza com "teve resposta do agente?" e "criou meal_log?" na janela seguinte.
 *
 * ALTA PRECISÃO de propósito: vira alerta no Telegram, então não pode dar lobo.
 * Só sinais FORTES de pedido de registro — foto/áudio (canal primário), verbo
 * de registro explícito, rótulo de refeição com ":", ou verbo de "comi". NÃO
 * casa nome de comida solto ("banana") pra não inflar falso-positivo.
 *
 * Cobre PT-BR (principal), EN e ES (idiomas suportados).
 */

// Verbo explícito de registrar (imperativo/infinitivo do paciente: "registre",
// "anota aí", "adiciona ao café", "salva isso"). + register/log/add (EN),
// registra/anota/agrega/apunta (ES).
const REGISTER_VERB =
  /\b(?:registr(?:a|ar|e|ei|em|ou)|anot(?:a|ar|e|ei|ou)|adicion(?:a|ar|e|ei|ou)|salv(?:a|ar|e|ei)|lan[çc](?:a|ar|e)|register|log(?:s|ged)?|add|agreg(?:a|ar)|apunt(?:a|ar))\b/i

// Rótulo de refeição declarado com ":" — "Almoço:", "Café da manhã:", "Jantar :".
// O ":" é o sinal forte (paciente declarando a refeição). Sem ":" não casa, pra
// evitar pegar conversa solta ("o almoço estava bom").
// Sem \b antes do ":": "manhã" termina em vogal acentuada (não-ASCII) e o \b
// ASCII falha entre "ã" e ":" (ambos não-\w) — mesma pegadinha do fake-write-detector.
const MEAL_LABEL =
  /\b(?:caf[ée](?:\s+da\s+manh[ãa])?|almo[çc]o|jantar|lanche|ceia|sobremesa|breakfast|lunch|dinner|snack|desayuno|almuerzo|cena)\s*[:：]/i

// Verbo de "comi/jantei/almocei/tomei" — declaração de que comeu (PT/EN/ES).
// "ate" puro (EN) fica de fora: colide com "até" sem acento (falso-positivo PT).
const ATE_VERB =
  /\b(?:comi|comemos|jantei|almocei|lanchei|tomei|ceei|merendei|com[íi]|cen[ée]|eaten)\b/i

export interface RegRequestInput {
  /** Texto da mensagem do paciente (pode ser null em foto/áudio). */
  content: string | null
  /** content_type da mensagem: 'text' | 'image' | 'audio'. */
  contentType: string
}

/**
 * true quando a mensagem inbound é plausivelmente um pedido de registrar
 * comida (foto/áudio, verbo de registro, rótulo de refeição com ":", ou
 * verbo de "comi"). Determinístico e case-insensitive.
 */
export function looksLikeRegistrationRequest({ content, contentType }: RegRequestInput): boolean {
  // Foto do prato ou nota de voz: canal primário de registro — sempre exige
  // resposta do agente.
  if (contentType === 'image' || contentType === 'audio') return true
  if (!content) return false
  if (REGISTER_VERB.test(content)) return true
  if (MEAL_LABEL.test(content)) return true
  if (ATE_VERB.test(content)) return true
  return false
}
