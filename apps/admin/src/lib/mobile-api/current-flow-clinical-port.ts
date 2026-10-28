/** Inert mobile-only composition. A caller must supply every clinical effect and
 * the historical series source. No default route, flag, provider or activation. */
import {
  type FlowClinicalDraftCreate,
  type FlowClinicalDraftKey,
  type FlowClinicalDraftPort,
  type FlowClinicalRead,
  type MobileFlowClinicalPort,
  readFlowClinicalPolicy,
} from '@mpp/agent'
import { computePeriodSummary, type SnapshotForAgg } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { readClinicalRepresentation } from './clinical-representation'
import { readClinicalCalculationConfigRows } from './clinical-snapshot-calculation'
import type { CurrentClinicalAdmission } from './current-clinical-admission'
import type { ClinicalHttpDependencies } from './current-clinical-http'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { type CurrentClinicalStateSource, currentClinicalError } from './current-clinical-state'
import {
  bindCurrentFlowDraftAuthority,
  type CurrentFlowDraftAuthority,
  type CurrentFlowDraftContext,
  currentFlowDraftBinding,
  readCurrentFlowCreatedDraft,
  readCurrentFlowDraftContext,
  readCurrentFlowStoredDraft,
} from './current-flow-draft-authority'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import type { MobileRouteContext } from './route'

export interface ClinicalFlowPeriodRow extends SnapshotForAgg {
  date: string
  /** Server evidence for this exact closed day. Numbers alone are not proof. */
  balance_proven: boolean
}
export interface CurrentFlowClinicalDependencies extends ClinicalHttpDependencies {
  admission?: CurrentClinicalAdmission
  state: CurrentClinicalStateSource
  drafts: CurrentFlowDraftAuthority
  periodRows(
    client: ServiceClient,
    owner: string,
    from: string,
    to: string,
  ): Promise<ClinicalFlowPeriodRow[]>
}
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
function ageAt(date: string, birth: string | null) {
  if (!birth) return null
  return (
    Number(date.slice(0, 4)) - Number(birth.slice(0, 4)) - (date.slice(5) < birth.slice(5) ? 1 : 0)
  )
}
export function createCurrentFlowClinicalPort(
  context: MobileRouteContext,
  dependencies: CurrentFlowClinicalDependencies,
): MobileFlowClinicalPort & { drafts: FlowClinicalDraftPort } {
  const auth = freeze(structuredClone(context.auth)),
    owner = authenticatedReevaluationOwner(auth),
    client = context.supabase,
    url = context.request.url
  if (!readClinicalRepresentation(url).compatible) throw currentClinicalError('invalid_response')
  const createModel = dependencies.createReadModel.bind(dependencies),
    daily = dependencies.applyDaily.bind(dependencies),
    close = dependencies.closeDays.bind(dependencies),
    periodRows = dependencies.periodRows.bind(dependencies)
  const authority = bindCurrentFlowDraftAuthority(dependencies.drafts)
  const model = createModel(client)
  const today = model.today.bind(model),
    progress = model.progress.bind(model),
    preflight = model.preflight.bind(model)
  let initial: Promise<CurrentFlowDraftContext> | undefined
  let lastObserved: string | undefined
  function initialize() {
    if (!initial)
      initial = (async () => {
        const admission = await preflight(auth, url, 'today')
        const scope = Object.freeze({ auth, supabase: client, url, admission })
        await daily(scope)
        await close(scope)
        const captured = readCurrentFlowDraftContext(await authority.capture(), owner)
        lastObserved = captured.state.observed_at
        return captured
      })()
    return initial
  }
  async function revalidate() {
    const expected = await initialize(),
      current = readCurrentFlowDraftContext(await authority.capture(), owner)
    if (
      current.state.observed_at < (lastObserved ?? expected.state.observed_at) ||
      currentFlowDraftBinding(expected) !== currentFlowDraftBinding(current)
    )
      throw currentClinicalError('changed')
    lastObserved = current.state.observed_at
    return current.state
  }
  const turns = new Map<string, Promise<string>>()
  function draftKey(input: Readonly<FlowClinicalDraftKey>) {
    const suffix = input.domain === 'training' ? ':propoe_plano_treino' : ':propoe_plano_dieta'
    if (
      !['training', 'nutrition'].includes(input.domain) ||
      !/^[A-Za-z0-9._:/-]{8,200}$/.test(input.requestKey) ||
      !input.requestKey.endsWith(suffix)
    )
      throw currentClinicalError('invalid_response')
    return freeze({ domain: input.domain, requestKey: input.requestKey })
  }
  const drafts: FlowClinicalDraftPort = Object.freeze({
    async lookup(input: Readonly<FlowClinicalDraftKey>) {
      const fixed = draftKey(input)
      await revalidate()
      let original = turns.get(fixed.requestKey)
      if (!original) {
        original = authority.findTurn(fixed)
        turns.set(fixed.requestKey, original)
      }
      const sourceMessageId = await original,
        expected = await initialize()
      const result = await authority.lookup({ ...fixed, sourceMessageId, expected })
      await revalidate()
      return result === null ? null : readCurrentFlowStoredDraft(result)
    },
    async create(input: Readonly<FlowClinicalDraftCreate>) {
      const fixed = freeze(
          structuredClone({
            ...draftKey(input),
            status: input.status,
            payload: input.payload,
            uncertainFields: input.uncertainFields,
            originDetail: input.originDetail,
          }),
        ),
        original = turns.get(fixed.requestKey)
      if (!original) throw currentClinicalError('changed')
      await revalidate()
      const sourceMessageId = await original,
        expected = await initialize()
      const result = await authority.create({ ...fixed, sourceMessageId, expected })
      await revalidate()
      return readCurrentFlowCreatedDraft(result)
    },
  })
  return Object.freeze({
    async read() {
      await initialize()
      await revalidate()
      const [day, p] = await Promise.all([today(auth, url), progress(auth, url)])
      const state = await revalidate(),
        policy = readFlowClinicalPolicy(projectCurrentClinicalPublicPolicy(state)),
        blockBadges = new Set(
          readClinicalCalculationConfigRows(state.calculation_config)
            .config.badges.filter((b) => b.type === 'blocks')
            .map((b) => b.key),
        ),
        publicProgress =
          p === null
            ? null
            : {
                xp_total: p.xp_total,
                level: p.level,
                current_streak: p.current_streak,
                longest_streak: p.longest_streak,
                blocks_completed: p.blocks_completed,
                deficit_block: p.deficit_block,
                badges_earned: p.badges_earned.filter(
                  (key) =>
                    (!policy.hide.block && day.current_protocol === 'recomposicao') ||
                    !blockBadges.has(key),
                ),
              }
      if (!day.clinical_policy) throw currentClinicalError('invalid_response')
      const bound = await initialize()
      if (
        day.local_date !== bound.state.date ||
        (!policy.hide.calories &&
          day.targets.calories_kcal !== (bound.day?.calories_target ?? null)) ||
        (!policy.hide.protein && day.targets.protein_g !== (bound.day?.protein_target ?? null))
      )
        throw currentClinicalError('changed')
      const { clinical_policy: _policy, ...publicDay } = day
      const result: FlowClinicalRead = {
        version: 1,
        locale: state.body.locale,
        timezone: state.timezone,
        policy,
        today: publicDay,
        profile: {
          name: auth.patient.name,
          sex: state.body.sex,
          age: ageAt(state.date, state.body.birth_date),
          weight_kg: state.body.weight_kg,
          height_cm: state.body.height_cm,
          protocol: policy.hide.objective ? null : day.current_protocol,
          bf_percent: policy.hide.objective ? null : state.body.body_fat_percent,
        },
        progress: publicProgress,
      }
      // No raw health state, owner, epoch, hash, config or historical provenance.
      return freeze(result)
    },
    async period(period: 'semana' | 'mes') {
      const state = await revalidate(),
        to = state.date,
        n = period === 'semana' ? 7 : 30
      const date = new Date(`${to}T00:00:00Z`)
      date.setUTCDate(date.getUTCDate() - (n - 1))
      const from = date.toISOString().slice(0, 10)
      const rows = structuredClone(await periodRows(client, owner, from, to)),
        dates = new Set<string>()
      for (const row of rows) {
        if (
          !/^\d{4}-\d{2}-\d{2}$/.test(row.date) ||
          !Number.isFinite(Date.parse(`${row.date}T00:00:00Z`)) ||
          new Date(`${row.date}T00:00:00Z`).toISOString().slice(0, 10) !== row.date ||
          row.date < from ||
          row.date > to ||
          dates.has(row.date) ||
          typeof row.balance_proven !== 'boolean'
        )
          throw currentClinicalError('invalid_response')
        dates.add(row.date)
        for (const key of ['calories_consumed', 'protein_g', 'daily_balance'] as const)
          if (row[key] !== null && (typeof row[key] !== 'number' || !Number.isFinite(row[key])))
            throw currentClinicalError('invalid_response')
      }
      const after = await revalidate(),
        policy = projectCurrentClinicalPublicPolicy(after),
        summary = computePeriodSummary(rows)
      const balanceVisible =
        !policy.hide.balance &&
        rows.length > 0 &&
        rows.every((r) => r.balance_proven && r.daily_balance !== null)
      return freeze({
        periodo: period,
        from,
        to,
        ...summary,
        avgNetBalance: balanceVisible ? summary.avgNetBalance : null,
        clinical_policy: policy,
      })
    },
    async revalidate() {
      await revalidate()
    },
    drafts,
  })
}
