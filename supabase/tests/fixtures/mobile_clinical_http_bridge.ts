/** Real Progress HTTP wrapper, default services and readers; only the database
 * transport/Auth are replaced by the guarded parent's single rollback session.
 * This is not a deployed HTTP/PostgREST/native/Storage test. */
import assert from 'node:assert/strict'
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from '../../../apps/admin/src/lib/mobile-api/auth'
import { createClinicalCloseDaysEffect } from '../../../apps/admin/src/lib/mobile-api/clinical-close-days-effect'
import { createClinicalDailyEffect } from '../../../apps/admin/src/lib/mobile-api/clinical-daily-effect'
import {
  evaluateClinicalFirstPhase,
  projectClinicalFirstPhase,
} from '../../../apps/admin/src/lib/mobile-api/clinical-first-phase-calculation'
import { createClinicalFirstPhaseRoutes } from '../../../apps/admin/src/lib/mobile-api/clinical-first-phase-http'
import { createClinicalFirstPhaseService } from '../../../apps/admin/src/lib/mobile-api/clinical-first-phase-service'
import { createClinicalFullQuestionnaire } from '../../../apps/admin/src/lib/mobile-api/clinical-full-questionnaire'
import { createClinicalFullQuestionnaireRoutes } from '../../../apps/admin/src/lib/mobile-api/clinical-full-questionnaire-http'
import { createClinicalFullService } from '../../../apps/admin/src/lib/mobile-api/clinical-full-service'
import { createCurrentClinicalGetRoute } from '../../../apps/admin/src/lib/mobile-api/current-clinical-http'
import { createCurrentClinicalReadModel } from '../../../apps/admin/src/lib/mobile-api/current-clinical-read-model'
import { createSupabaseClinicalFirstPhaseRepository } from '../../../apps/admin/src/lib/mobile-api/supabase-clinical-first-phase'
import { createSupabaseClinicalFullRepository } from '../../../apps/admin/src/lib/mobile-api/supabase-clinical-full'
import { createSupabaseCurrentClinicalStateSource } from '../../../apps/admin/src/lib/mobile-api/supabase-current-clinical-state'

if (process.env.PERFORME_CLINICAL_HTTP_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw new Error('Explicit owned rollback parent required')
const iterator = createInterface({ input: process.stdin, crlfDelay: Infinity })[
  Symbol.asyncIterator
]()
const send = (value: unknown) => process.stdout.write(`${JSON.stringify(value)}\n`)
// Keep stdout exclusively for the parent protocol, including normal hook logs.
console.info = (...values: unknown[]) => console.error(...values)
let queue = Promise.resolve()
function request(packet: object): Promise<unknown> {
  const result = queue.then(async () => {
    send(packet)
    const value = await iterator.next()
    if (value.done) throw new Error('Parent closed before response')
    return JSON.parse(value.value)
  })
  queue = result.then(
    () => {},
    () => {},
  )
  return result
}
const uid = (n: number) => `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`
const a = uid(3800),
  b = uid(3801),
  cases: string[] = []
let active = a,
  numericReads = 0,
  operation = 3900,
  dailyKeys = 0
const calls: { owner: string; name: string }[] = []
function clientFor(owner: string): ServiceClient {
  return {
    rpc: async (name: string, args: Record<string, unknown>) => {
      assert.equal(args.p_user_id, owner)
      calls.push({ owner, name })
      return request({ type: 'rpc', owner, name, args })
    },
    from(table: string) {
      let columns = '',
        single = false,
        limit: number | null = null
      const filters: { column: string; op: string; value: unknown }[] = []
      let order: { column: string; ascending: boolean } | null = null
      const read = Promise.resolve().then(() => {
        if (table === 'user_profiles' || columns.includes('xp_total')) numericReads++
        return request({ type: 'select', owner, table, columns, filters, order, limit, single })
      })
      const filter = (column: string, op: string, value: unknown) => {
        filters.push({ column, op, value })
        return builder
      }
      const builder = Object.assign(read, {
        select(value: string) {
          columns = value
          return builder
        },
        eq(column: string, value: unknown) {
          return filter(column, '=', value)
        },
        gte(column: string, value: unknown) {
          return filter(column, '>=', value)
        },
        lte(column: string, value: unknown) {
          return filter(column, '<=', value)
        },
        lt(column: string, value: unknown) {
          return filter(column, '<', value)
        },
        order(column: string, options: { ascending: boolean }) {
          order = { column, ascending: options.ascending }
          return builder
        },
        limit(value: number) {
          limit = value
          return builder
        },
        maybeSingle() {
          single = true
          return builder
        },
      })
      return builder
    },
  } as unknown as ServiceClient
}
const clients = new Map([
  [a, clientFor(a)],
  [b, clientFor(b)],
])
function auth(owner: string): MobileAuthContext {
  return {
    userId: owner,
    authUserId: uid(3899),
    accessToken: 'synthetic-local-only',
    identity: { id: uid(3899), email: null, emailConfirmedAt: null },
    patient: {
      id: owner,
      authUserId: uid(3899),
      email: null,
      name: 'Synthetic QA',
      locale: 'pt-BR',
      timezone: 'Asia/Tokyo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
}
const effect = createClinicalDailyEffect({
  nextOperationKey: () => {
    dailyKeys++
    return uid(++operation)
  },
})
const close = createClinicalCloseDaysEffect({
  env: {
    MOBILE_DAY_CLOSE_FROM: '2026-01-01',
    MOBILE_DAY_CLOSE_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
    NEXT_PUBLIC_SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
  },
  nextOperationKey: () => uid(++operation),
})
const route = createCurrentClinicalGetRoute(
  'progress',
  {
    createServiceClient: () => {
      const client = clients.get(active)
      assert(client)
      return client
    },
    authenticate: async () => auth(active),
    authorizeEntitlement: async () => {},
    createRequestId: () => 'request-id-is-not-an-operation-uuid',
  },
  {
    createReadModel: (client) =>
      createCurrentClinicalReadModel(client, createSupabaseCurrentClinicalStateSource(client)),
    applyDaily: effect,
    closeDays: close,
  },
  () => false,
)
async function get(owner: string, compatible = true) {
  active = owner
  const response = await route(
    new Request(
      'https://local.invalid/api/mobile/v1/progress' +
        (compatible ? '?clinical_policy=current_clinical_v1' : ''),
    ),
  )
  return { response, body: await response.json() }
}
async function witness() {
  return request({ type: 'witness' }) as Promise<Record<string, unknown>>
}

try {
  const first = await get(a)
  assert.equal(first.response.status, 200)
  assert.equal(first.body.data.xp_total, 55)
  assert.equal(first.body.data.current_streak, 3)
  assert.equal(first.body.data.current_protocol, 'manutencao')
  assert.equal(first.body.data.clinical_policy.target_source, 'assigned_phase')
  assert.equal(first.response.headers.get('Cache-Control'), 'no-store')
  assert.equal(first.response.headers.get('Vary'), 'Authorization')
  let state = await witness()
  assert.equal(state.applications_A, 1)
  assert.equal(state.closed_A, 1)
  assert.equal(state.day_target_A, 2000)
  assert.equal(state.source_day_target_A, 2100)
  assert.equal(state.source_day_closed_A, false)
  assert.equal(state.today_snapshots_A, 1)
  assert.equal(state.today_target_A, 2100)
  cases.push('actual_HTTP_preflight_default_daily_closer_and_fresh_Progress_SQL')
  const second = await get(a)
  assert.equal(second.response.status, 200)
  assert.equal(second.body.data.xp_total, 55)
  state = await witness()
  assert.equal(state.applications_A, 1)
  assert.equal(state.closed_A, 1)
  cases.push('repeat_GET_does_not_duplicate_daily_stage_or_day_XP')
  await request({ type: 'arm_risk', owner: a })
  const beforeNumeric = numericReads
  const refused = await get(a)
  assert.equal(refused.response.status, 409)
  assert.equal(refused.body.error.code, 'mobile_clinical_daily_changed')
  assert.equal(numericReads, beforeNumeric)
  state = await witness()
  assert.equal(state.applications_A, 1)
  assert.equal(state.xp_A, 55)
  cases.push('controlled_SQL_context_change_refuses_HTTP_before_closer_and_numeric_read')
  const held = await get(a)
  assert.equal(held.response.status, 200)
  assert.equal(held.body.data.clinical_policy.pause_weight_loss_guidance, true)
  state = await witness()
  assert.equal(state.applications_A, 2)
  assert.equal(state.application_state_A, 'suspended')
  assert.equal(state.suspended_target_A, 2100)
  assert.equal(state.guarded_calculation_null, true)
  cases.push('assigned_HOLD_reaches_real_SQL_suspension_without_new_target')
  const offset = calls.length,
    beforeKeys = dailyKeys
  const old = await get(b, false)
  assert.equal(old.response.status, 409)
  assert.equal(old.body.error.code, 'clinical_client_update_required')
  assert.equal(dailyKeys, beforeKeys)
  assert.equal(calls.length, offset + 1)
  const noPlan = await get(b)
  assert.equal(noPlan.response.status, 200)
  assert.equal(noPlan.body.data.xp_total, 42)
  assert.equal(noPlan.body.data.blocks_completed, null)
  assert.equal(noPlan.body.data.deficit_block, null)
  assert.equal(noPlan.body.data.current_protocol, null)
  assert.equal(noPlan.body.data.clinical_policy.recording_allowed, true)
  assert.equal(dailyKeys, beforeKeys)
  assert(
    !calls
      .slice(offset)
      .some(
        (v) =>
          v.owner === b &&
          [
            'get_mobile_clinical_daily_receipt',
            'get_mobile_clinical_daily_context',
            'apply_mobile_clinical_daily',
          ].includes(v.name),
      ),
  )
  state = await witness()
  assert.equal(state.applications_B, 0)
  assert.equal(state.daily_keys_B, 0)
  assert.equal(state.phase_B, null)
  assert.equal(state.xp_A, 55)
  cases.push('actual_no_plan_signup_HTTP_masks_targets_preserves_XP_and_has_no_daily_writer')
  const started = (await request({ type: 'start_no_plan', owner: b })) as { cycle: string }
  const fullClient = clients.get(b)
  assert(fullClient)
  const fullService = createClinicalFullService({
    enabled: true,
    repository: createSupabaseClinicalFullRepository(fullClient),
  })
  const formRoutes = createClinicalFullQuestionnaireRoutes(
    {
      enabled: true,
      createService: () =>
        createClinicalFullQuestionnaire({
          enabled: true,
          repository: createSupabaseClinicalFullRepository(fullClient),
        }),
    },
    {
      authenticate: async () => auth(b),
      authorizeEntitlement: async () => {},
      createServiceClient: () => fullClient,
      createRequestId: () => 'owned-health-full-form',
    },
  )
  const formRequest = (value: unknown) =>
    new Request('https://bodyflow.test/api/mobile/v1/reevaluation/form', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(value),
    })
  const healthDraft = {
    form: {
      version: 1,
      phase: null,
      kind: 'EARLY_FULL',
      activityPurpose: 'normal',
      preference: null,
      answers: {
        weightKg: 81,
        strengthSessions: null,
        hunger: null,
        energy: null,
        adherence: null,
        strengthProgression: null,
        fatPerception: null,
        difficultToMaintain: null,
        activity: null,
        healthCheck: { kind: 'none' },
        professionalConversationConfirmed: true,
      },
    },
    choice: { kind: 'keep' },
    measureConfirmed: false,
    bodyFat: null,
  }
  const prepareRequest = {
    kind: 'EARLY_FULL',
    cycleId: started.cycle,
    operationKey: uid(3950),
    input: {
      activityPurpose: healthDraft.form.activityPurpose,
      answers: healthDraft.form.answers,
      preference: null,
      choice: healthDraft.choice,
      measureConfirmed: healthDraft.measureConfirmed,
      bodyFat: null,
    },
  }
  const describedHealth = await formRoutes.DESCRIBE(
    formRequest({ kind: 'EARLY_FULL', cycleId: started.cycle, activityPurpose: 'normal' }),
  )
  assert.equal(describedHealth.status, 200)
  const healthDescription = (await describedHealth.json()).data
  assert.deepEqual(
    healthDescription.questions.map((q: { key: string }) => q.key),
    ['weightKg', 'healthCheck', 'professionalConversationConfirmed'],
  )
  assert.equal(healthDescription.preference_question, null)
  assert.equal(healthDescription.body_fat.status, 'not_required')
  assert(!JSON.stringify(healthDescription).includes('noPlanOrigin'))
  cases.push(
    'actual_health_only_public_HTTP_descriptor_contains_only_weight_health_and_professional_question',
  )
  const { choice: _healthChoice, ...healthPublicDraft } = prepareRequest.input
  const assessedHealth = await formRoutes.ASSESS(
    formRequest({ kind: 'EARLY_FULL', cycleId: started.cycle, input: healthPublicDraft }),
  )
  assert.equal(assessedHealth.status, 200)
  const healthAssessment = (await assessedHealth.json()).data
  assert.equal(healthAssessment.actions.length, 1)
  assert.deepEqual(healthAssessment.actions[0].choice, { kind: 'keep' })
  assert.deepEqual(healthAssessment.actions[0].targets, { calories_kcal: null, protein_g: null })
  cases.push('actual_health_only_public_HTTP_assessment_cannot_offer_first_phase_or_targets')
  const beforeHealthDraft = await witness()
  const unadmitted = await formRoutes.ASSESS(
    formRequest({
      kind: 'EARLY_FULL',
      cycleId: started.cycle,
      input: {
        ...healthPublicDraft,
        answers: {
          ...healthPublicDraft.answers,
          healthCheck: { kind: 'risks', items: ['reduced_intake'] },
        },
      },
    }),
  )
  assert.equal(unadmitted.status, 200)
  assert.equal((await unadmitted.json()).data.status, 'health_declaration_required')
  assert.deepEqual(await witness(), beforeHealthDraft)
  cases.push('actual_health_draft_is_read_only_and_cannot_admit_or_clear_a_HOLD')
  const prepared = await fullService.preparePublic(auth(b), prepareRequest)
  const normalizedForm = prepared.command.form
  assert(normalizedForm.phase === null)
  assert.equal(normalizedForm.noPlanOrigin.kind, 'confirmed_no_plan')
  assert.equal(prepared.package.proposal.clearHold, true)
  assert.equal(prepared.package.form.phase, null)
  assert.deepEqual(prepared.package.proposal.targets, {
    beforeKcal: null,
    beforeProtein: null,
    afterKcal: null,
    afterProtein: null,
    formulaAfterKcal: null,
  })
  assert.deepEqual(prepared.package.proposal.episode, {
    difficultyCount: null,
    ledgerSteps: null,
    schedule: null,
    maintenanceSince: null,
  })
  cases.push(
    'actual_health_only_service_binds_signup_origin_and_calculates_no_phase_targets_or_episode',
  )
  const confirmRequest = {
    ...prepareRequest,
    previewId: prepared.preview.preview_id,
    operationKey: uid(3951),
  }
  const confirmed = await fullService.confirmPublic(auth(b), confirmRequest)
  assert.equal(confirmed.result.kind, 'EARLY_FULL')
  assert.equal(confirmed.result.safety_revision, '2')
  state = await witness()
  assert.equal(state.full_B, 1)
  assert.equal(state.weights_B, 1)
  assert.equal(state.weight_B, 81)
  assert.equal(state.clears_B, 1)
  assert.deepEqual(
    state.health_B && (state.health_B as { hold_active: boolean }).hold_active,
    false,
  )
  assert.equal(state.due_B, confirmed.result.next_due_date)
  assert.equal(state.day_events_B, 0)
  assert.equal(state.snapshots_B, 0)
  cases.push(
    'actual_service_and_public_command_SQL_clear_weight_and_calendar_without_clinical_targets',
  )
  const cleared = await get(b)
  assert.equal(cleared.response.status, 200)
  assert.equal(cleared.body.data.clinical_policy.phase_selection_pending, true)
  assert.equal(cleared.body.data.clinical_policy.target_source, 'unavailable')
  assert.equal(dailyKeys, beforeKeys)
  state = await witness()
  assert.equal(state.episodes_B, 0)
  assert.equal(state.phase_B, null)
  assert.equal(state.xp_B, 42)
  assert.equal(state.applications_B, 0)
  cases.push('actual_health_FULL_clear_does_not_assign_first_phase_or_resume_targets')
  const beforeFirstPhase = await witness()
  const firstPhaseRpc = fullClient.rpc.bind(fullClient) as unknown as (
    name: string,
    args: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: unknown }>
  const firstPhaseRaw = await firstPhaseRpc('get_mobile_clinical_first_phase_context', {
    p_user_id: b,
  })
  assert.equal(firstPhaseRaw.error, null)
  const firstPhaseOptions = projectClinicalFirstPhase(firstPhaseRaw.data, b)
  assert.equal(firstPhaseOptions.availability, 'available')
  assert.equal(firstPhaseOptions.options.find((v) => v.phase === 'ganho_massa')?.status, 'blocked')
  const firstPhase = evaluateClinicalFirstPhase(firstPhaseRaw.data, b, { phase: 'recomposicao' })
  assert.equal(firstPhase.package.targets.afterKcal, 1413)
  assert.equal(firstPhase.package.targets.afterProtein, 121.5)
  assert.equal(firstPhase.package.formulaBodyFat.percent, null)
  assert.deepEqual(await witness(), beforeFirstPhase)
  cases.push(
    'actual_first_phase_capture_and_core_preview_after_clear_without_any_assignment_or_write',
  )
  const firstService = createClinicalFirstPhaseService({
    enabled: true,
    repository: createSupabaseClinicalFirstPhaseRepository(fullClient),
  })
  const firstRoutes = createClinicalFirstPhaseRoutes(
    {
      enabled: true,
      createService: (client) =>
        createClinicalFirstPhaseService({
          enabled: true,
          repository: createSupabaseClinicalFirstPhaseRepository(client),
        }),
    },
    {
      createServiceClient: () => fullClient,
      authenticate: async () => auth(b),
      authorizeEntitlement: async () => {},
      createRequestId: () => 'first-phase-public-qa',
    },
  )
  const publicChoices = await firstRoutes.GET(
    new Request('https://local.invalid/api/mobile/v1/protocol/first-phase'),
  )
  assert.equal(publicChoices.status, 200)
  const choicesData = (await publicChoices.json()).data
  assert.deepEqual(Object.keys(choicesData).sort(), [
    'availability',
    'date',
    'effective_date',
    'missing',
    'options',
    'professional_assessment_recommended',
    'version',
  ])
  assert.equal(choicesData.availability, 'available')
  cases.push('actual_public_first_choices_HTTP_excludes_age_BMI_health_answers_and_provenance')
  const firstPrepareRequest = { operationKey: uid(3970), selection: { phase: 'recomposicao' } }
  const previewResponse = await firstRoutes.PREVIEW(
    new Request('https://local.invalid/api/mobile/v1/protocol/first-phase/preview', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'idempotency-key': firstPrepareRequest.operationKey,
      },
      body: JSON.stringify({ phase: 'recomposicao' }),
    }),
  )
  assert.equal(previewResponse.status, 200)
  const previewData = (await previewResponse.json()).data
  assert.deepEqual(Object.keys(previewData).sort(), [
    'effective_date',
    'expires_at',
    'phase',
    'preview_id',
    'targets',
    'version',
  ])
  assert.deepEqual(previewData.targets, { calories_kcal: 1413, protein_g: 121.5 })
  cases.push(
    'actual_public_first_preview_HTTP_uses_service_core_SQL_and_only_offers_official_display_fields',
  )
  const firstPrepared = await firstService.prepare(auth(b), firstPrepareRequest)
  assert.deepEqual(firstPrepared.package, firstPhase.package)
  state = await witness()
  assert.equal(state.first_previews_B, 1)
  assert.equal(state.first_confirmations_B, 0)
  assert.equal(state.episodes_B, 0)
  assert.equal(state.phase_B, null)
  assert.equal(state.snapshots_B, 0)
  cases.push('actual_first_phase_service_persists_server_preview_without_any_clinical_assignment')
  const firstConfirmRequest = {
    operationKey: uid(3971),
    previewId: firstPrepared.preview_id,
    selection: { phase: 'recomposicao' },
  }
  const confirmResponse = await firstRoutes.CONFIRM(
    new Request('https://local.invalid/api/mobile/v1/protocol/first-phase/confirm', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'idempotency-key': firstConfirmRequest.operationKey,
      },
      body: JSON.stringify({ preview_id: firstConfirmRequest.previewId, phase: 'recomposicao' }),
    }),
  )
  assert.equal(confirmResponse.status, 200)
  const confirmData = (await confirmResponse.json()).data
  assert.deepEqual(Object.keys(confirmData).sort(), [
    'confirmation_id',
    'confirmed_at',
    'effective_date',
    'phase',
    'version',
  ])
  assert.equal(confirmData.confirmation_id, previewData.preview_id)
  assert.equal(confirmData.phase, 'recomposicao')
  cases.push(
    'actual_public_first_confirmation_HTTP_returns_original_receipt_without_private_or_current_target_claim',
  )
  const firstConfirmed = await firstService.confirm(auth(b), firstConfirmRequest)
  state = await witness()
  assert.equal(state.first_confirmations_B, 1)
  assert.equal(state.first_keys_B, 1)
  assert.equal(state.phase_B, 'recomposicao')
  assert.equal(state.episodes_B, 1)
  assert.equal(state.full_B, beforeFirstPhase.full_B)
  assert.equal(state.due_B, beforeFirstPhase.due_B)
  assert.equal(state.current_target_B, 1413)
  assert.equal(state.xp_B, 42)
  assert.equal(state.day_events_B, 0)
  cases.push(
    'actual_first_phase_service_core_public_SQL_confirmation_creates_genuine_source_without_FULL_or_XP_effects',
  )
  const afterFirstGet = await get(b)
  assert.equal(afterFirstGet.response.status, 200)
  assert.equal(afterFirstGet.body.data.clinical_policy.phase_selection_pending, false)
  state = await witness()
  assert.equal(state.applications_B, 1)
  assert.equal(state.current_target_B, 1413)
  assert.equal(state.full_B, beforeFirstPhase.full_B)
  assert.equal(state.due_B, beforeFirstPhase.due_B)
  assert.equal(state.xp_B, 42)
  cases.push('actual_HTTP_GET_accepts_first_phase_daily_source_and_preserves_calendar_and_XP')
  const newCivil = (await request({ type: 'advance_first_civil_day', owner: b })) as {
    date: string
  }
  assert(newCivil.date > firstConfirmed.result.decision_date)
  const firstNextDayGet = await get(b)
  assert.equal(firstNextDayGet.response.status, 200)
  state = await witness()
  assert.equal(state.applications_B, 2)
  assert.equal(state.current_target_B, 1413)
  assert.equal(state.full_B, beforeFirstPhase.full_B)
  assert.equal(state.episodes_B, 1)
  assert.equal(state.due_B, beforeFirstPhase.due_B)
  assert.equal(state.xp_B, 42)
  cases.push('actual_next_civil_day_HTTP_GET_calculates_from_first_phase_before_any_following_FULL')
  const initialEpisode = state.effective_episode_B as Record<string, unknown>
  const assignedStart = (await request({ type: 'start_assigned', owner: b })) as { cycle: string }
  const assignedInput = {
    ...healthDraft,
    form: {
      ...healthDraft.form,
      phase: 'recomposicao',
      answers: {
        ...healthDraft.form.answers,
        strengthSessions: 4,
        hunger: 'moderada',
        energy: 'boa',
        adherence: 'bem_consistente',
        professionalConversationConfirmed: null,
      },
    },
  }
  const assignedRequest = {
    kind: 'EARLY_FULL',
    cycleId: assignedStart.cycle,
    operationKey: uid(3980),
    input: {
      activityPurpose: assignedInput.form.activityPurpose,
      answers: assignedInput.form.answers,
      preference: null,
      choice: assignedInput.choice,
      measureConfirmed: assignedInput.measureConfirmed,
      bodyFat: null,
    },
  }
  const describedAssigned = await formRoutes.DESCRIBE(
    formRequest({ kind: 'EARLY_FULL', cycleId: assignedStart.cycle, activityPurpose: 'normal' }),
  )
  assert.equal(describedAssigned.status, 200)
  assert.equal(
    (await describedAssigned.json()).data.questions.some(
      (q: { key: string }) => q.key === 'strengthSessions',
    ),
    true,
  )
  const { choice: _assignedChoice, ...assignedDraft } = assignedRequest.input
  const assessedAssigned = await formRoutes.ASSESS(
    formRequest({ kind: 'EARLY_FULL', cycleId: assignedStart.cycle, input: assignedDraft }),
  )
  assert.equal(assessedAssigned.status, 200)
  assert.equal(
    (await assessedAssigned.json()).data.actions.some(
      (a: { choice: { kind: string } }) => a.choice.kind === 'keep',
    ),
    true,
  )
  cases.push(
    'actual_first_phase_to_following_FULL_public_HTTP_adapts_form_and_offers_only_evaluated_actions',
  )
  const assignedPrepared = await fullService.preparePublic(auth(b), assignedRequest)
  assert.equal(assignedPrepared.package.form.phase, 'recomposicao')
  const assignedAck = await fullService.confirmPublic(auth(b), {
    ...assignedRequest,
    previewId: assignedPrepared.preview.preview_id,
    operationKey: uid(3981),
  })
  state = await witness()
  const followingEpisode = state.latest_episode_B as Record<string, unknown>
  assert.equal(state.full_B, 2)
  assert.equal(state.episodes_B, 2)
  assert.equal(followingEpisode.first_phase_id, null)
  assert.equal(followingEpisode.review_id, assignedAck.result.review_id)
  assert.equal(followingEpisode.previous_event_id, initialEpisode.event_id)
  for (const name of [
    'episode_id',
    'entry_date',
    'start_weight_kg',
    'start_height_cm',
    'start_body_fat_percent',
    'start_training_frequency',
    'difficulty_count',
    'ledger_steps',
    'maintenance_since',
  ])
    assert.deepEqual(followingEpisode[name], initialEpisode[name], `Inherited initial ${name}`)
  assert.equal(state.xp_B, 42)
  cases.push(
    'actual_following_FULL_core_service_public_SQL_inherits_real_initial_episode_without_fabricated_review',
  )
  await request({ type: 'risk_no_plan', owner: b })
  const afterRisk = await witness()
  assert.equal((afterRisk.health_B as { hold_active: boolean }).hold_active, true)
  let replayOffset = calls.length
  assert.deepEqual(await fullService.preparePublic(auth(b), prepareRequest), prepared)
  assert.deepEqual(await fullService.confirmPublic(auth(b), confirmRequest), confirmed)
  assert.deepEqual(
    calls.slice(replayOffset).map((v) => v.name),
    ['get_mobile_clinical_full_command', 'get_mobile_clinical_full_command_receipt'],
  )
  assert.deepEqual(await witness(), afterRisk)
  cases.push('health_FULL_original_prepare_confirm_replay_keeps_later_risk_without_recapture')
  replayOffset = calls.length
  assert.deepEqual(await firstService.prepare(auth(b), firstPrepareRequest), firstPrepared)
  assert.deepEqual(await firstService.confirm(auth(b), firstConfirmRequest), firstConfirmed)
  assert.deepEqual(
    calls.slice(replayOffset).map((v) => v.name),
    ['get_mobile_clinical_first_phase_prepared', 'get_mobile_clinical_first_phase_receipt'],
  )
  assert.deepEqual(await witness(), afterRisk)
  cases.push('first_phase_prepare_and_confirmation_ACKs_after_new_risk_are_receipt_only')
  const firstAliasRequest = { ...firstConfirmRequest, operationKey: uid(3972) }
  const firstAlias = await firstService.confirm(auth(b), firstAliasRequest)
  assert.deepEqual(firstAlias.result, firstConfirmed.result)
  const afterFirstAlias = await witness()
  assert.equal(afterFirstAlias.effects_B, afterRisk.effects_B)
  assert.equal(afterFirstAlias.first_keys_B, Number(afterRisk.first_keys_B) + 1)
  cases.push('first_phase_alias_adds_only_original_key_and_preserves_the_new_risk')
  const aliasRequest = { ...confirmRequest, operationKey: uid(3952) }
  replayOffset = calls.length
  const alias = await fullService.confirmPublic(auth(b), aliasRequest)
  assert.deepEqual(alias.result, confirmed.result)
  assert.deepEqual(
    calls.slice(replayOffset).map((v) => v.name),
    ['get_mobile_clinical_full_command_receipt', 'confirm_mobile_clinical_full_command'],
  )
  const afterAlias = await witness()
  assert.equal(afterAlias.effects_B, afterFirstAlias.effects_B)
  assert.equal(afterAlias.confirmation_keys_B, Number(afterRisk.confirmation_keys_B) + 1)
  cases.push('health_FULL_alias_binds_only_original_receipt_without_clearing_new_risk')
  await request({ type: 'reset_no_plan', owner: b })
  const afterReset = await witness()
  replayOffset = calls.length
  assert.deepEqual(await fullService.preparePublic(auth(b), prepareRequest), prepared)
  assert.deepEqual(await fullService.confirmPublic(auth(b), confirmRequest), confirmed)
  assert.deepEqual(await fullService.confirmPublic(auth(b), aliasRequest), alias)
  assert.deepEqual(
    calls.slice(replayOffset).map((v) => v.name),
    [
      'get_mobile_clinical_full_command',
      'get_mobile_clinical_full_command_receipt',
      'get_mobile_clinical_full_command_receipt',
    ],
  )
  assert.deepEqual(await witness(), afterReset)
  cases.push(
    'health_FULL_original_and_alias_replay_after_reset_resurrect_no_profile_targets_or_health',
  )
  replayOffset = calls.length
  assert.deepEqual(await firstService.prepare(auth(b), firstPrepareRequest), firstPrepared)
  assert.deepEqual(await firstService.confirm(auth(b), firstConfirmRequest), firstConfirmed)
  assert.deepEqual(await firstService.confirm(auth(b), firstAliasRequest), firstAlias)
  assert.deepEqual(
    calls.slice(replayOffset).map((v) => v.name),
    [
      'get_mobile_clinical_first_phase_prepared',
      'get_mobile_clinical_first_phase_receipt',
      'get_mobile_clinical_first_phase_receipt',
    ],
  )
  assert.deepEqual(await witness(), afterReset)
  cases.push(
    'first_phase_original_and_alias_ACKs_after_actual_reset_do_not_restore_phase_or_targets',
  )
  send({
    type: 'done',
    status: 'PASS_ACTUAL_HTTP_DEFAULT_CLINICAL_SERVICES_SQL',
    cases,
    rpc_calls: calls.length,
    numeric_reads: numericReads,
    real_HTTP_wrapper: true,
    real_default_services_and_readers: true,
    actual_public_RPC_SQL: true,
    deployed_HTTP: false,
    PostgREST: false,
    Native: false,
    Storage: false,
    remote_operations: 0,
  })
} catch (error) {
  console.error(error instanceof Error ? error.message : 'Local HTTP bridge failure')
  send({ type: 'failure', status: 'FAIL_ACTUAL_HTTP_DEFAULT_CLINICAL_SERVICES_SQL' })
  process.exitCode = 1
}
