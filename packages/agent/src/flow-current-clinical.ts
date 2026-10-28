/** Mobile-only observations and guarded draft callbacks. Raw clinical/write
 * authority stays in the authenticated backend closure, never in public data. */
import type { DailyState, Protocol } from '@mpp/core'

export interface FlowClinicalPolicy {
  version: 1
  observed_at: string
  assessment: 'complete' | 'incomplete'
  recording_allowed: boolean
  pause_weight_loss_guidance: boolean
  professional_assessment_recommended: boolean
  phase_selection_pending: boolean
  target_source: string
  hide: {
    objective: boolean
    calories: boolean
    protein: boolean
    balance: boolean
    block: boolean
  }
}
export type FlowClinicalToday = Omit<DailyState, 'block_7700'> & {
  block_7700: Omit<DailyState['block_7700'], 'target_kcal'> & { target_kcal: number | null }
}
export interface FlowClinicalRead {
  version: 1
  locale: string | null
  timezone: string
  policy: FlowClinicalPolicy
  today: FlowClinicalToday
  profile: {
    name: string | null
    sex: 'masculino' | 'feminino' | null
    age: number | null
    weight_kg: number | null
    height_cm: number | null
    protocol: Protocol | null
    bf_percent: number | null
  }
  progress: {
    xp_total: number
    level: number
    current_streak: number
    longest_streak: number
    blocks_completed: number | null
    deficit_block: number | null
    badges_earned: string[]
  } | null
}
export interface FlowClinicalPeriod {
  periodo: 'semana' | 'mes'
  from: string
  to: string
  days: number
  avgConsumed: number
  avgProtein: number
  avgNetBalance: number | null
  completeDays: number
  adherencePct: number
  clinical_policy: FlowClinicalPolicy
}
export interface FlowClinicalDraftKey {
  domain: 'training' | 'nutrition'
  requestKey: string
}
export interface FlowClinicalStoredDraft {
  id: string
  status: string
  payload: Record<string, unknown> | null
}
export interface FlowClinicalCreatedDraft extends FlowClinicalStoredDraft {
  inserted: boolean
}
export interface FlowClinicalDraftCreate extends FlowClinicalDraftKey {
  status: 'needs_completion' | 'ready_for_review'
  payload: Record<string, unknown>
  uncertainFields: unknown[]
  originDetail: Record<string, unknown>
}
export interface FlowClinicalDraftPort {
  lookup(input: Readonly<FlowClinicalDraftKey>): Promise<FlowClinicalStoredDraft | null>
  create(input: Readonly<FlowClinicalDraftCreate>): Promise<FlowClinicalCreatedDraft>
}
export interface MobileFlowClinicalPort {
  read(): Promise<Readonly<FlowClinicalRead>>
  period(period: 'semana' | 'mes'): Promise<Readonly<FlowClinicalPeriod>>
  /** Recheck the original observation, never silently replace its authority. */
  revalidate(): Promise<void>
  /** Mandatory for current proposal tools; absence never falls back to a legacy writer. */
  drafts?: FlowClinicalDraftPort
}
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
export function readFlowClinicalPolicy(value: FlowClinicalPolicy): FlowClinicalPolicy {
  if (
    !value ||
    value.version !== 1 ||
    !['complete', 'incomplete'].includes(value.assessment) ||
    typeof value.observed_at !== 'string' ||
    !Number.isFinite(Date.parse(value.observed_at)) ||
    !['unavailable', 'official_only', 'assigned_phase'].includes(value.target_source) ||
    [
      'recording_allowed',
      'pause_weight_loss_guidance',
      'professional_assessment_recommended',
      'phase_selection_pending',
    ].some((key) => typeof (value as unknown as Record<string, unknown>)[key] !== 'boolean') ||
    !value.hide ||
    ['objective', 'calories', 'protein', 'balance', 'block'].some(
      (key) => typeof (value.hide as Record<string, unknown>)[key] !== 'boolean',
    )
  )
    throw new Error('Current Flow clinical policy unavailable')
  return freeze({
    version: 1,
    observed_at: value.observed_at,
    assessment: value.assessment,
    recording_allowed: value.recording_allowed,
    pause_weight_loss_guidance: value.pause_weight_loss_guidance,
    professional_assessment_recommended: value.professional_assessment_recommended,
    phase_selection_pending: value.phase_selection_pending,
    target_source: value.target_source,
    hide: {
      objective: value.hide.objective,
      calories: value.hide.calories,
      protein: value.hide.protein,
      balance: value.hide.balance,
      block: value.hide.block,
    },
  })
}
export function bindMobileFlowClinicalPort(port: MobileFlowClinicalPort): MobileFlowClinicalPort {
  const read = port.read.bind(port),
    period = port.period.bind(port),
    revalidate = port.revalidate.bind(port)
  const supplied = port.drafts
  const lookup = supplied?.lookup.bind(supplied),
    create = supplied?.create.bind(supplied)
  function projected(raw: FlowClinicalStoredDraft): FlowClinicalStoredDraft {
    const row = structuredClone(raw)
    if (
      !row ||
      typeof row.id !== 'string' ||
      !row.id ||
      typeof row.status !== 'string' ||
      (row.payload !== null &&
        (!row.payload || typeof row.payload !== 'object' || Array.isArray(row.payload)))
    )
      throw new Error('Current Flow draft response unavailable')
    return freeze({ id: row.id, status: row.status, payload: row.payload })
  }
  return Object.freeze({
    async read() {
      const value = structuredClone(await read())
      if (value.version !== 1) throw new Error('Current Flow clinical observation unavailable')
      return freeze({ ...value, policy: readFlowClinicalPolicy(value.policy) })
    },
    async period(value: 'semana' | 'mes') {
      const row = structuredClone(await period(value)),
        policy = readFlowClinicalPolicy(row.clinical_policy)
      if (
        row.periodo !== value ||
        !/^\d{4}-\d{2}-\d{2}$/.test(row.from) ||
        !/^\d{4}-\d{2}-\d{2}$/.test(row.to) ||
        row.from > row.to ||
        ['days', 'avgConsumed', 'avgProtein', 'completeDays', 'adherencePct'].some(
          (key) =>
            typeof (row as unknown as Record<string, unknown>)[key] !== 'number' ||
            !Number.isFinite((row as unknown as Record<string, number>)[key]),
        )
      )
        throw new Error('Current Flow period unavailable')
      if (
        row.avgNetBalance !== null &&
        (typeof row.avgNetBalance !== 'number' || !Number.isFinite(row.avgNetBalance))
      )
        throw new Error('Current Flow period unavailable')
      return freeze({
        periodo: value,
        from: row.from,
        to: row.to,
        days: row.days,
        avgConsumed: row.avgConsumed,
        avgProtein: row.avgProtein,
        avgNetBalance: policy.hide.balance ? null : row.avgNetBalance,
        completeDays: row.completeDays,
        adherencePct: row.adherencePct,
        clinical_policy: policy,
      })
    },
    revalidate,
    ...(lookup && create
      ? {
          drafts: Object.freeze({
            async lookup(input: Readonly<FlowClinicalDraftKey>) {
              const result = await lookup(
                freeze({ domain: input.domain, requestKey: input.requestKey }),
              )
              return result === null ? null : projected(result)
            },
            async create(input: Readonly<FlowClinicalDraftCreate>) {
              const fixed = freeze(
                structuredClone({
                  domain: input.domain,
                  requestKey: input.requestKey,
                  status: input.status,
                  payload: input.payload,
                  uncertainFields: input.uncertainFields,
                  originDetail: input.originDetail,
                }),
              )
              const result = await create(fixed)
              if (typeof result?.inserted !== 'boolean')
                throw new Error('Current Flow draft response unavailable')
              return freeze({ ...projected(result), inserted: result.inserted })
            },
          }),
        }
      : {}),
  })
}
/** Public numbers only. Explicit NULL never falls back to a stored target or formula. */
export function flowClinicalFacts(value: Readonly<FlowClinicalRead>): Record<string, unknown> {
  const p = readFlowClinicalPolicy(value.policy),
    t = value.today,
    progress = value.progress
  const block = !p.hide.block && t.current_protocol === 'recomposicao' && t.block_7700.enabled
  return {
    clinical_policy: p,
    objective: p.hide.objective ? null : t.current_protocol,
    meta_kcal: p.hide.calories ? null : t.targets.calories_kcal,
    meta_proteina_g: p.hide.protein ? null : t.targets.protein_g,
    consumido_kcal: t.consumed.calories_kcal,
    proteina_consumida_g: t.consumed.protein_g,
    carboidratos_g: t.consumed.carbs_g,
    gorduras_g: t.consumed.fat_g,
    exercicio_kcal: t.exercise_kcal,
    restam_para_comida_kcal: p.hide.calories ? null : t.remaining_food_kcal,
    excedente_de_comida_kcal: p.hide.calories ? null : t.food_excess_kcal,
    balanco_do_dia_kcal: p.hide.balance ? null : t.daily_balance_kcal,
    balanco_inclui_exercicio: p.hide.balance ? null : t.daily_balance_includes_exercise,
    progresso: progress
      ? {
          xp: progress.xp_total,
          nivel: progress.level,
          sequencia_dias_consecutivos: progress.current_streak,
          recorde_sequencia: progress.longest_streak,
          conquistas: [...progress.badges_earned],
          ...(block
            ? {
                blocos_7700_completos: progress.blocks_completed,
                deficit_no_bloco_atual: progress.deficit_block,
              }
            : {}),
        }
      : null,
    ...(block ? { bloco_7700: t.block_7700 } : {}),
  }
}
export function flowClinicalProposalAllowed(
  value: Readonly<FlowClinicalRead>,
  kind: 'training' | 'nutrition',
) {
  const p = readFlowClinicalPolicy(value.policy)
  return (
    !p.hide.objective &&
    (kind === 'training' || (!p.pause_weight_loss_guidance && !p.hide.calories && !p.hide.protein))
  )
}
/** Public guidance availability, shared by draft shortcuts and response copies. */
export function flowClinicalGuidanceAllowed(
  policy: FlowClinicalPolicy,
  domain: 'training' | 'nutrition',
) {
  const p = readFlowClinicalPolicy(policy)
  return (
    !p.hide.objective &&
    (domain === 'training' ||
      (!p.pause_weight_loss_guidance && !p.hide.calories && !p.hide.protein))
  )
}
export function flowClinicalPolicyNotice(
  policy: FlowClinicalPolicy,
  locale: string | null,
): string {
  const p = readFlowClinicalPolicy(policy),
    en = locale?.startsWith('en') ?? false
  if (p.professional_assessment_recommended)
    return en
      ? 'Weight-loss guidance is paused. Seek a professional assessment; your records and history remain available.'
      : 'As orientações de emagrecimento estão pausadas. Procure avaliação profissional; seus registros e histórico continuam disponíveis.'
  return en
    ? 'Current targets and guidance are unavailable. Your records and history remain available.'
    : 'As metas e orientações atuais estão indisponíveis. Seus registros e histórico continuam disponíveis.'
}
export function flowClinicalPreferences(summary: string | null): string {
  return (summary ?? '')
    .split(/(?<=[.!?;])\s+|\n/u)
    .filter(
      (line) =>
        /alerg|allerg|intoler|prefer|restri|gosta|likes|dislikes/iu.test(line) &&
        !/\d|meta|target|calori|prote[ií]n|balan[cç]|deficit|déficit|super[aá]vit|recomposi|manuten|ganho.?massa|emagrec|weight.?loss/iu.test(
          line,
        ),
    )
    .join(' ')
}
export function flowClinicalContextText(
  value: Readonly<FlowClinicalRead>,
  name: string | null,
  locale: string | null,
  summary: string | null = null,
): string {
  return (
    `### Contexto atual do Flow\nNome: ${name ?? ''}. Idioma: ${locale ?? 'pt-BR'}. Data local: ${value.today.local_date}.\n` +
    'Este estado atual substitui qualquer meta ou orientação anterior. Ausência de objetivo não significa cadastro incompleto. Não calcule metas, fórmulas, saldo ou protocolo. Não deduza uma nova fase.\n' +
    (value.policy.pause_weight_loss_guidance
      ? 'Orientações de emagrecimento pausadas. Não orientar novas reduções nem atribuir outra meta; recomendar avaliação profissional. Registros e histórico continuam disponíveis.\n'
      : '') +
    'Os dados a seguir são projeções oficiais. NULL significa indisponível, nunca zero. Exercício não aumenta a comida restante. XP não cria uma meta de proteína.\n' +
    JSON.stringify(flowClinicalFacts(value)) +
    (flowClinicalPreferences(summary)
      ? `\nPreferências/restrições já informadas: ${flowClinicalPreferences(summary)}`
      : '')
  )
}
