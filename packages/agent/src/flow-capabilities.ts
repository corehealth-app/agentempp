/** Public capabilities of the current app, in the method's original order.
 * Availability describes the whole family; a partial feature does not enable it.
 * Keep this list independent of account data and model-generated promises.
 */
export type FlowCapabilitiesLocale = 'pt-BR' | 'en'

type Capability = {
  id: number
  key: string
} & ({ available: true; copy: Record<FlowCapabilitiesLocale, string> } | { available: false })

export const flowCapabilities = [
  {
    id: 1,
    key: 'estimates_and_official_targets',
    available: true,
    // consulta_metricas / renderOfficialTargets: available official data only.
    copy: {
      'pt-BR':
        'Estimativas e metas oficiais: explico os valores disponíveis no app, conforme seus dados.',
      en: 'Estimates and official targets: I explain the values available in the app, based on your data.',
    },
  },
  {
    id: 2,
    key: 'meal_photo_and_text',
    available: true,
    // Registrar creates a meal draft; media also requires availability/access.
    copy: {
      'pt-BR':
        'Refeições por texto ou foto em Registrar: preparo um rascunho para você revisar e confirmar. A foto depende do recurso disponível e da permissão de câmera ou fotos.',
      en: 'Meals by text or photo in Register: I prepare a draft for you to review and confirm. Photos depend on feature availability and camera or photo permission.',
    },
  },
  {
    id: 3,
    key: 'daily_balance_and_summary',
    available: true,
    // loadOfficialDailyState / renderFlowDayStatus: confirmed records, no writes.
    copy: {
      'pt-BR':
        'Balanço e resumo do dia: consulto os registros confirmados e os valores oficiais disponíveis. Exercício não aumenta o que resta para comida.',
      en: 'Daily balance and summary: I use confirmed records and available official values. Exercise does not increase your remaining food allowance.',
    },
  },
  {
    id: 4,
    key: 'meal_plan_suggestion',
    available: true,
    // propoe_plano_dieta creates a draft; confirmPlanDraft confirms only the plan.
    copy: {
      'pt-BR':
        'Sugestão de cardápio: preparo um rascunho em Plano com suas preferências e restrições, para revisar e confirmar. Confirmar o plano não registra comida consumida.',
      en: 'Meal-plan suggestion: I prepare a draft in Plan with your preferences and restrictions, for review and confirmation. Confirming a plan does not record food you have eaten.',
    },
  },
  { id: 5, key: 'complete_recipes', available: false },
  { id: 6, key: 'body_fat_from_photo', available: false },
  { id: 7, key: 'automatic_protocol_transitions', available: false },
  {
    id: 8,
    key: 'workout_suggestion',
    available: true,
    // propoe_plano_treino creates a plan draft; it does not log workout execution.
    copy: {
      'pt-BR':
        'Sugestão de treino: preparo um rascunho conforme os dias, equipamentos e nível informados, para você revisar e confirmar no app.',
      en: 'Workout suggestion: I prepare a draft based on the days, equipment and level you provide, for you to review and confirm in the app.',
    },
  },
  {
    id: 9,
    key: 'educational_chat',
    available: true,
    // The authenticated chat can explain; these descriptions confer no tool access.
    copy: {
      'pt-BR':
        'Dúvidas educativas no chat: explico conceitos de alimentação, treino e uso do app. Sou um assistente de IA; essas explicações não substituem avaliação profissional, diagnóstico ou tratamento.',
      en: 'Educational questions in chat: I explain food, exercise and app concepts. I am an AI assistant; these explanations do not replace professional assessment, diagnosis or treatment.',
    },
  },
  { id: 10, key: 'complete_reports_and_automatic_adjustment', available: false },
  { id: 11, key: 'proactive_tips', available: false },
] as const satisfies readonly Capability[]

/** Match the complete message. Mixed requests keep their original pipeline. */
export function flowCapabilitiesQuestionLocale(text: string): FlowCapabilitiesLocale | null {
  const question = text
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/\s+/gu, ' ')
    .trim()
    .replace(/[.!?]+$/u, '')
    .trim()
  switch (question) {
    case 'o que voce faz':
    case 'o que voce pode fazer':
      return 'pt-BR'
    case 'what do you do':
    case 'what can you do':
      return 'en'
    default:
      return null
  }
}

/** Static copy; no account values, cache, tool call or implicit confirmation. */
export function renderFlowCapabilities(locale: FlowCapabilitiesLocale): string {
  const intro =
    locale === 'en'
      ? 'I am Flow, the Performe AI assistant. Here is what you can currently do:'
      : 'Sou o Flow, assistente do Performe AI. Veja o que você pode fazer atualmente:'
  const lines = flowCapabilities.flatMap((capability) =>
    capability.available ? [`• ${capability.copy[locale]}`] : [],
  )
  return [intro, '', ...lines].join('\n')
}
