/**
 * Botões interativos no onboarding (Roberto 2026-06-01).
 *
 * Roberto pediu: pra perguntas de onboarding com resposta DISCRETA (sexo, fome,
 * água, alimentação organizada, protocolo), trocar texto livre por botão.
 *
 * Como funciona:
 * - Regra de prompt instrui o LLM a usar a tag `[BTN:field:Opt1=val1|Opt2=val2]`
 *   no FIM da pergunta. Ex:
 *     "Você é homem ou mulher?\n[BTN:sex:Homem=masculino|Mulher=feminino]"
 * - Pipeline detecta a tag, separa body (pergunta) + buttons (opções), envia
 *   interactive em vez de text.
 * - Quando paciente toca botão (id `btn_<field>_<value>`), o handler chama
 *   `cadastra_dados_iniciais({[field]: value})` direto. LLM continua no próximo
 *   turno com o dado já gravado.
 *
 * Fields suportados (limite WhatsApp = 3 reply buttons; perguntas com 4+
 * opções como activity_level usam outro padrão — ver Fase 2).
 */

export type OnboardingField =
  | 'sex'
  | 'hunger_level'
  | 'water_intake'
  | 'food_organization'
  | 'current_protocol'
  | 'activity_level'
  | 'training_frequency'

export const ONBOARDING_FIELD_VALUES: Record<OnboardingField, string[]> = {
  sex: ['masculino', 'feminino'],
  hunger_level: ['pouca', 'moderada', 'muita'],
  water_intake: ['pouco', 'moderado', 'bastante'],
  food_organization: ['sim', 'nao'],
  current_protocol: ['recomposicao', 'ganho_massa', 'manutencao'],
  // Activity level: 5 opções (precisa List Message). Fase 2 Roberto 2026-06-01.
  activity_level: ['sedentario', 'leve', 'moderado', 'alto', 'atleta'],
  // Training frequency: 0-7 dias/semana. Number coerção feita no handler.
  training_frequency: ['0', '1', '2', '3', '4', '5', '6', '7'],
}

/** Fields que SÓ vão via List Message (têm 4+ opções). */
export const LIST_ONLY_FIELDS: OnboardingField[] = ['activity_level', 'training_frequency']

export interface OnboardingButtonOption {
  /** Texto que aparece no botão (máx 20 chars no WhatsApp). */
  label: string
  /** Valor canônico que vai pro `cadastra_dados_iniciais`. Tem que bater com o enum do schema. */
  value: string
}

export interface OnboardingButtonProposal {
  /** Pergunta pro paciente (texto antes da tag). */
  body: string
  /** Campo do user_profiles que vai ser preenchido pelo tap. */
  field: OnboardingField
  /** Opções (máx 3 — WhatsApp limit). */
  options: OnboardingButtonOption[]
}

/**
 * Tag: [BTN:field:Label1=value1|Label2=value2|Label3=value3]
 * Permite | (pipe) como separador de opções e = pra separar label/value.
 *
 * Body = texto antes da tag (sem trailing newlines).
 * Retorna null se: sem tag, tag malformada, field não suportado, opções
 * inválidas (vazias, > 3, valor fora do enum), ou body vazio.
 */
const BTN_TAG_REGEX = /\[BTN:([a-z_]+):([^\]]+)\]/i

export function parseOnboardingButtonTag(text: string): OnboardingButtonProposal | null {
  if (!text) return null
  const m = text.match(BTN_TAG_REGEX)
  if (!m) return null

  const field = m[1]!.toLowerCase() as OnboardingField
  if (!(field in ONBOARDING_FIELD_VALUES)) return null

  const rawOpts = m[2]!.split('|').map((s) => s.trim()).filter(Boolean)
  if (rawOpts.length < 2 || rawOpts.length > 3) return null

  const validValues = ONBOARDING_FIELD_VALUES[field]
  const options: OnboardingButtonOption[] = []
  for (const opt of rawOpts) {
    const eqIdx = opt.indexOf('=')
    if (eqIdx === -1) return null
    const label = opt.slice(0, eqIdx).trim()
    const value = opt.slice(eqIdx + 1).trim().toLowerCase()
    if (!label || !value) return null
    if (label.length > 20) return null
    if (!validValues.includes(value)) return null
    options.push({ label, value })
  }

  const body = text.slice(0, m.index!).trimEnd()
  if (!body) return null

  return { body, field, options }
}

/**
 * ID do botão de onboarding: `btn_<field>_<value>`.
 * Distingue dos botões de registro (`confirm_<uuid>` / `edit_<uuid>`) — o
 * handler usa esse prefixo pra rotear pra `cadastra_dados_iniciais`.
 */
export function makeOnboardingButtonId(field: OnboardingField, value: string): string {
  return `btn_${field}_${value}`
}

const ONBOARDING_BTN_ID_RE = /^btn_([a-z_0-9]+)$/i

export function parseOnboardingButtonId(
  id: string,
): { field: OnboardingField; value: string } | null {
  const m = id.match(ONBOARDING_BTN_ID_RE)
  if (!m) return null
  // Field pode ter underscore (food_organization, training_frequency).
  // Value pode ser número (0-7 pra training_frequency). Match testando contra
  // lista de fields conhecidos — pega o que começa com 'field_'.
  const rest = m[1]!
  for (const field of Object.keys(ONBOARDING_FIELD_VALUES) as OnboardingField[]) {
    if (rest.startsWith(field + '_')) {
      const value = rest.slice(field.length + 1)
      if (ONBOARDING_FIELD_VALUES[field].includes(value)) {
        return { field, value }
      }
    }
  }
  return null
}

/**
 * Tag de List Message: [LIST:field:Label1=val1|Label2=val2|...|Label10=val10]
 * Aceita 4-10 opções. Pra perguntas com até 3, use [BTN:...] (mais simples).
 */
const LIST_TAG_REGEX = /\[LIST:([a-z_]+):([^\]]+)\]/i

export interface OnboardingListProposal {
  body: string
  field: OnboardingField
  /** Texto do botão "abrir lista" (max 20 chars). Default: "Escolher" */
  buttonText: string
  options: OnboardingButtonOption[]
}

export function parseOnboardingListTag(text: string): OnboardingListProposal | null {
  if (!text) return null
  const m = text.match(LIST_TAG_REGEX)
  if (!m) return null

  const field = m[1]!.toLowerCase() as OnboardingField
  if (!(field in ONBOARDING_FIELD_VALUES)) return null

  const rawOpts = m[2]!.split('|').map((s) => s.trim()).filter(Boolean)
  if (rawOpts.length < 2 || rawOpts.length > 10) return null

  const validValues = ONBOARDING_FIELD_VALUES[field]
  const options: OnboardingButtonOption[] = []
  for (const opt of rawOpts) {
    const eqIdx = opt.indexOf('=')
    if (eqIdx === -1) return null
    const label = opt.slice(0, eqIdx).trim()
    const value = opt.slice(eqIdx + 1).trim().toLowerCase()
    if (!label || !value) return null
    if (label.length > 24) return null
    if (!validValues.includes(value)) return null
    options.push({ label, value })
  }

  const body = text.slice(0, m.index!).trimEnd()
  if (!body) return null

  return { body, field, buttonText: 'Escolher', options }
}
