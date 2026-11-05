/** Dormant server composition. There are deliberately no default clinical
 * writers/clients/flags. Final SQL CAS, closer and native integration are still
 * required before any route may opt in. */
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import { readClinicalRepresentation } from './clinical-representation'
import { trendsQuerySchema } from './contracts'
import type {
  ClinicalReadAdmission,
  ClinicalReadEndpoint,
  createCurrentClinicalReadModel,
} from './current-clinical-read-model'
import { MobileApiError, mobileSuccess } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createMobileRoute, type MobileRouteRuntime } from './route'

export interface ClinicalHttpEffectScope {
  readonly auth: MobileAuthContext
  readonly supabase: ServiceClient
  readonly url: string
  readonly admission: ClinicalReadAdmission
}
export interface ClinicalHttpDependencies {
  createReadModel(client: ServiceClient): ReturnType<typeof createCurrentClinicalReadModel>
  /** Required, authority-aware ports. No request ID or client clock is offered
   * as an operation key. A server-owned key and current SQL CAS are mandatory. */
  applyDaily(scope: ClinicalHttpEffectScope): Promise<void>
  closeDays(scope: ClinicalHttpEffectScope): Promise<void>
}
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
function fixedRuntime(runtime: MobileRouteRuntime | undefined) {
  if (!runtime) return undefined
  return Object.freeze({
    authenticate: runtime.authenticate.bind(runtime),
    authorizeEntitlement: runtime.authorizeEntitlement.bind(runtime),
    createServiceClient: runtime.createServiceClient.bind(runtime),
    createRequestId: runtime.createRequestId.bind(runtime),
  })
}

export type ClinicalTodayData = Awaited<
  ReturnType<ReturnType<typeof createCurrentClinicalReadModel>['today']>
>
export type ClinicalTodayEnergyData = Awaited<
  ReturnType<ReturnType<typeof createCurrentClinicalReadModel>['todayWithEnergy']>
>
export type ClinicalTodayEnrichment = <T extends ClinicalTodayData | ClinicalTodayEnergyData>(
  client: ServiceClient,
  owner: string,
  data: T,
) => Promise<T>
export function createCurrentClinicalReadGetRoute(
  endpoint: ClinicalReadEndpoint,
  runtime: MobileRouteRuntime | undefined,
  dependencies: ClinicalHttpDependencies,
  enrichToday?: ClinicalTodayEnrichment,
) {
  const createReadModel = dependencies.createReadModel.bind(dependencies)
  const applyDaily = dependencies.applyDaily.bind(dependencies)
  const closeDays = dependencies.closeDays.bind(dependencies)
  const decorateToday = enrichToday
  return createMobileRoute(async (context) => {
    // Bind everything needed by this request before the first asynchronous read.
    const auth = freeze(structuredClone(context.auth))
    authenticatedReevaluationOwner(auth)
    const url = context.request.url,
      client = context.supabase,
      requestId = context.requestId
    const representation = readClinicalRepresentation(url)
    if (endpoint !== 'today' && representation.dayEnergyCompatible)
      throw new MobileApiError(
        400,
        'unsupported_day_energy_endpoint',
        'Day energy representation is only supported for Today',
      )
    const query =
      endpoint === 'trends'
        ? trendsQuerySchema.parse(Object.fromEntries(representation.search.entries()))
        : null
    const model = createReadModel(client)
    const admission = await model.preflight(auth, url, endpoint)
    if (endpoint === 'today' || endpoint === 'progress') {
      const scope = Object.freeze({ auth, supabase: client, url, admission })
      await applyDaily(scope)
      await closeDays(scope)
    }
    // Never publish the preflight policy: effects can legitimately change the
    // state. Every reader performs its own fresh pre/post authority captures.
    if (endpoint === 'today') {
      const data = representation.dayEnergyCompatible
        ? await model.todayWithEnergy(
            auth,
            url,
            decorateToday ? (owner, current) => decorateToday(client, owner, current) : undefined,
          )
        : await model.today(
            auth,
            url,
            decorateToday ? (owner, current) => decorateToday(client, owner, current) : undefined,
          )
      return mobileSuccess(data, requestId)
    }
    if (endpoint === 'progress') return mobileSuccess(await model.progress(auth, url), requestId)
    if (endpoint === 'plan') return mobileSuccess(await model.plan(auth, url), requestId)
    if (endpoint === 'protocol') return mobileSuccess(await model.protocol(auth, url), requestId)
    if (endpoint === 'trends' && query)
      return mobileSuccess(await model.trends(auth, url, query), requestId)
    throw new Error('Unknown clinical reader endpoint')
  }, fixedRuntime(runtime))
}
