import { z } from 'zod'

/** n10 v1: this catalog is shared by draft, SQL wire validation and future consumers. */
export const HEALTH_RISK_CODES = Object.freeze([
  'unintended_weight_loss',
  'reduced_intake',
  'persistent_fatigue_weakness_dizziness',
  'menstrual_change',
  'loss_of_control_eating',
  'appetite_weight_treatment',
  'professional_diet',
  'pregnant_or_breastfeeding',
] as const)
export type HealthRiskCode = (typeof HEALTH_RISK_CODES)[number]

export const HEALTH_RISK_ITEMS = Object.freeze(
  [
    {
      code: HEALTH_RISK_CODES[0],
      label: 'Perdi peso sem querer',
      applicability: 'all',
      declaredNoPlan: false,
      hideProtein: false,
    },
    {
      code: HEALTH_RISK_CODES[1],
      label: 'Estou comendo muito menos do que o planejado ou pulando refeições',
      applicability: 'all',
      declaredNoPlan: false,
      hideProtein: false,
    },
    {
      code: HEALTH_RISK_CODES[2],
      label: 'Cansaço forte, fraqueza ou tontura que não passam',
      applicability: 'all',
      declaredNoPlan: false,
      hideProtein: false,
    },
    {
      code: HEALTH_RISK_CODES[3],
      label: 'Menstruação irregular ou ausente',
      applicability: 'feminino',
      declaredNoPlan: false,
      hideProtein: false,
    },
    {
      code: HEALTH_RISK_CODES[4],
      label: 'Senti que perdi o controle sobre o quanto estava comendo',
      applicability: 'all',
      declaredNoPlan: false,
      hideProtein: false,
    },
    {
      code: HEALTH_RISK_CODES[5],
      label: 'Uso remédio ou faço tratamento que muda o apetite ou o peso',
      applicability: 'all',
      declaredNoPlan: false,
      hideProtein: false,
    },
    {
      code: HEALTH_RISK_CODES[6],
      label: 'Tenho uma condição em que um profissional controla a minha alimentação ou a proteína',
      applicability: 'all',
      declaredNoPlan: false,
      hideProtein: true,
    },
    {
      code: HEALTH_RISK_CODES[7],
      label: 'Estou grávida ou amamentando',
      applicability: 'feminino',
      declaredNoPlan: true,
      hideProtein: false,
    },
  ].map((item) => Object.freeze(item)),
)

export const HEALTH_CHECK_QUESTION =
  'Alguma destas situações vale para você agora? Marque todas que valerem.'
export const PROFESSIONAL_CONVERSATION_DECLARATION =
  'Já conversei com um profissional sobre o que informei.'
export const REEVALUATION_OPT_OUT_LABEL = 'Prefiro não responder'

/** Normalize only absence/explicit opt-out; never coerce numeric strings into zero. */
export function unknownDraftAnswer(value: unknown): unknown {
  return value === undefined ||
    value === 'prefiro_nao_responder' ||
    (typeof value === 'string' && value.trim() === '')
    ? null
    : value
}

export const healthRiskCodeSchema = z.enum(HEALTH_RISK_CODES)
export const healthRiskSetSchema = z
  .array(healthRiskCodeSchema)
  .min(1)
  .max(8)
  .refine((items) => new Set(items).size === items.length, 'Duplicate health risk')
  .transform((items) => HEALTH_RISK_CODES.filter((code) => items.includes(code)))

/** A draft is not a declaration. None/opt-out never clear or modify a stored HOLD. */
export const healthCheckDraftSchema = z.preprocess(
  unknownDraftAnswer,
  z
    .discriminatedUnion('kind', [
      z.object({ kind: z.literal('none') }).strict(),
      z.object({ kind: z.literal('risks'), items: healthRiskSetSchema }).strict(),
    ])
    .nullable(),
)
export type HealthCheckDraft = z.infer<typeof healthCheckDraftSchema>
