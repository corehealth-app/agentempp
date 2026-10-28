/** Actual evaluator/repository/public SQL for REGULAR/ROUTINE. Other phases, deployed
 * HTTP, native UI and Storage require their own qualification. */
import assert from 'node:assert/strict'
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from '../../../apps/admin/src/lib/mobile-api/auth'
import { readClinicalFullContext } from '../../../apps/admin/src/lib/mobile-api/clinical-full-authority'
import { createClinicalFullEntryRoutes } from '../../../apps/admin/src/lib/mobile-api/clinical-full-entry'
import { evaluateClinicalFull } from '../../../apps/admin/src/lib/mobile-api/clinical-full-evaluation'
import { createClinicalFullRoutes } from '../../../apps/admin/src/lib/mobile-api/clinical-full-http'
import { clinicalFullPublicCandidateId } from '../../../apps/admin/src/lib/mobile-api/clinical-full-public-command'
import { createClinicalFullQuestionnaire } from '../../../apps/admin/src/lib/mobile-api/clinical-full-questionnaire'
import { createClinicalFullQuestionnaireRoutes } from '../../../apps/admin/src/lib/mobile-api/clinical-full-questionnaire-http'
import { createClinicalFullService } from '../../../apps/admin/src/lib/mobile-api/clinical-full-service'
import {
  projectCurrentClinicalState,
  readCurrentClinicalState,
} from '../../../apps/admin/src/lib/mobile-api/current-clinical-state'
import { createSupabaseClinicalFullRepository } from '../../../apps/admin/src/lib/mobile-api/supabase-clinical-full'
import { createSupabaseCurrentClinicalStateSource } from '../../../apps/admin/src/lib/mobile-api/supabase-current-clinical-state'
import { createSupabaseHealthHoldRepository } from '../../../apps/admin/src/lib/mobile-api/supabase-health-hold'

if (process.env.PERFORME_CLINICAL_FULL_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw new Error('Explicit owned rollback parent required')
const iterator = createInterface({ input: process.stdin, crlfDelay: Infinity })[
  Symbol.asyncIterator
]()
const send = (value: unknown) => process.stdout.write(`${JSON.stringify(value)}\n`)
async function request(packet: object): Promise<unknown> {
  send(packet)
  const response = await iterator.next()
  if (response.done) throw new Error('Parent closed before response')
  return JSON.parse(response.value)
}
const uid = (n: number) => `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`
async function run() {
  const initial = (await request({ type: 'scope' })) as { user: string; cycle: string }
  const kind =
    process.env.PERFORME_CLINICAL_FULL_SCENARIO !== 'regular'
      ? ('TRANSITION_FULL' as const)
      : ('REGULAR' as const)
  const unassigned = process.env.PERFORME_CLINICAL_FULL_SCENARIO === 'legacy_unassigned'
  const entryPhase = (process.env.PERFORME_CLINICAL_FULL_ENTRY_PHASE ?? 'recomposicao') as
    | 'recomposicao'
    | 'manutencao'
    | 'ganho_massa'
  assert(['recomposicao', 'manutencao', 'ganho_massa'].includes(entryPhase))
  assert(unassigned || entryPhase === 'recomposicao')
  const changedPhase = unassigned && entryPhase !== 'recomposicao'
  const expectedKcal =
    entryPhase === 'manutencao' ? 2495 : entryPhase === 'ganho_massa' ? 2620 : 1599
  const expectedProtein = 126
  const expectedRoutineKcal =
    entryPhase === 'manutencao' ? 2777 : entryPhase === 'ganho_massa' ? 2916 : 1599
  const scope = { userId: initial.user, kind, cycleId: initial.cycle }
  const calls: string[] = []
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push(name)
      return request({ type: 'rpc', name, args })
    },
  } as unknown as ServiceClient
  const repository = createSupabaseClinicalFullRepository(client)
  const service = createClinicalFullService({ enabled: true, repository })
  const auth: MobileAuthContext = {
    userId: initial.user,
    authUserId: uid(4299),
    accessToken: 'local-synthetic-context',
    identity: { id: uid(4299), email: null, emailConfirmedAt: null },
    patient: {
      id: initial.user,
      authUserId: uid(4299),
      email: null,
      name: null,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
  const cases: string[] = []
  const entryRoutes = createClinicalFullEntryRoutes(
    { enabled: true },
    {
      authenticate: async () => auth,
      authorizeEntitlement: async () => {},
      createServiceClient: () => client,
      createRequestId: () => 'owned-full-entry-qa',
    },
  )
  const entryResponse = await entryRoutes.GET(
    new Request('https://bodyflow.test/api/mobile/v1/reevaluation'),
  )
  assert.equal(entryResponse.status, 200)
  const entry = (await entryResponse.json()).data
  assert.equal(entry.availability, 'available')
  assert.equal(entry.cycle.id, scope.cycleId)
  assert.equal(entry.cycle.kind, kind)
  for (const field of ['signup_generation', 'opened_at', 'source_hash', 'user_id'])
    assert(!JSON.stringify(entry).includes(field))
  cases.push('actual_public_entry_projects_server_calendar_and_scope_without_private_generation')
  const startResponse = await entryRoutes.START(
    new Request('https://bodyflow.test/api/mobile/v1/reevaluation/start', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'idempotency-key': uid(4219) },
      body: JSON.stringify({ reason: null }),
    }),
  )
  assert.equal(startResponse.status, 200)
  assert.deepEqual((await startResponse.json()).data.cycle, entry.cycle)
  cases.push('actual_public_start_with_no_client_kind_or_clock_resumes_actual_occurrence')
  const raw = await repository.capture(scope)
  const context = readClinicalFullContext(raw, scope)
  if (kind === 'TRANSITION_FULL') {
    assert.equal(context.facts.anchor.authority.kind, 'legacy_transition')
    assert.equal(context.facts.profile.onboarding_completed_at, null)
    assert.equal(context.facts.anchor.clock.base_date, context.facts.anchor.clock.due_date)
  }
  const beforePhase = unassigned ? await request({ type: 'phase_witness' }) : null
  const currentSource = createSupabaseCurrentClinicalStateSource(client)
  const currentBefore = await currentSource.capture({ userId: initial.user, mode: 'profile' })
  const beforeState = readCurrentClinicalState(currentBefore, initial.user)
  assert.equal(beforeState.first_completion, false)
  assert.equal(beforeState.signup_generation, context.facts.anchor.signup_generation)
  assert.equal(
    beforeState.generation_authority?.kind,
    kind === 'REGULAR' ? 'signup_receipt' : 'legacy_transition',
  )
  assert.equal(projectCurrentClinicalState(beforeState).phaseSelectionPending, false)
  assert.equal(
    projectCurrentClinicalState(beforeState).targetSource,
    unassigned ? 'official_only' : 'assigned_phase',
  )
  if (kind === 'TRANSITION_FULL')
    assert.equal(beforeState.generation_token?.onboarding_completed_at, null)
  cases.push(
    'actual_current_source_consumes_legacy_or_signup_proof_before_FULL_without_fabricated_marker',
  )
  const candidate = context.facts.protocol_authority.body_fat_candidate
  assert(candidate?.availability === 'available')
  const evaluated = evaluateClinicalFull(raw, scope, {
    form: {
      version: 1,
      phase: unassigned ? null : 'recomposicao',
      ...(unassigned ? { legacyOrigin: context.facts.protocol_authority.phase_origin } : {}),
      kind,
      activityPurpose: 'normal',
      preference: null,
      answers: {
        weightKg: changedPhase ? 70 : 84,
        strengthSessions: 4,
        hunger: 'moderada',
        energy: unassigned ? null : 'boa',
        adherence: unassigned ? null : 'bem_consistente',
        strengthProgression: null,
        fatPerception: null,
        difficultToMaintain: null,
        activity: null,
        healthCheck: { kind: 'none' },
        professionalConversationConfirmed: null,
      },
    },
    choice: unassigned ? { kind: 'phase', phase: entryPhase } : { kind: 'keep' },
    measureConfirmed: false,
    bodyFat: {
      confirmed: true,
      sourceHash: candidate.source_hash,
      meanHundredths: candidate.mean_hundredths,
    },
  })
  const bundle = evaluated.package
  if (kind === 'TRANSITION_FULL') {
    assert.equal(bundle.proposal.episode.difficultyCount, unassigned && !changedPhase ? 0 : null)
    assert.deepEqual(bundle.proposal.episode.ledgerSteps, changedPhase ? [] : null)
  }
  assert.deepEqual(bundle.proposal.targets, {
    beforeKcal: 1700,
    beforeProtein: 120,
    afterKcal: expectedKcal,
    afterProtein: expectedProtein,
    formulaAfterKcal: expectedKcal,
  })
  const publicInput = {
    activityPurpose: evaluated.command.form.activityPurpose,
    answers: evaluated.command.form.answers,
    preference: evaluated.command.form.preference,
    choice: evaluated.command.choice,
    measureConfirmed: evaluated.command.measureConfirmed,
    bodyFat: {
      confirmed: true,
      candidateId: clinicalFullPublicCandidateId(scope, evaluated.command.bodyFat),
    },
  }
  const questionnaire = createClinicalFullQuestionnaireRoutes(
    {
      enabled: true,
      createService: () => createClinicalFullQuestionnaire({ enabled: true, repository }),
    },
    {
      authenticate: async () => auth,
      authorizeEntitlement: async () => {},
      createServiceClient: () => client,
      createRequestId: () => 'owned-full-public-qa',
    },
  )
  const post = (body: unknown, key?: string) =>
    new Request('https://bodyflow.test/api/mobile/v1/reevaluation/form', {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...(key ? { 'idempotency-key': key } : {}) },
      body: JSON.stringify(body),
    })
  const described = await questionnaire.DESCRIBE(
    post({ kind: scope.kind, cycleId: scope.cycleId, activityPurpose: 'normal' }),
  )
  assert.equal(described.status, 200)
  const description = (await described.json()).data
  assert.equal(description.body_fat.percent, changedPhase ? 18 : 24)
  assert.equal(description.body_fat.candidate_id, publicInput.bodyFat.candidateId)
  assert.equal(description.photo_requirement.required, true)
  for (const privateKey of ['source_hash', 'asset_id', 'signup_epoch', 'context_hash'])
    assert(!JSON.stringify(description).includes(privateKey))
  cases.push(
    'actual_REGULAR_public_HTTP_descriptor_binds_three_processed_new_photos_to_opaque_display_identity',
  )
  const { choice: _choice, ...publicDraft } = publicInput
  const assessed = await questionnaire.ASSESS(
    post({ kind: scope.kind, cycleId: scope.cycleId, input: publicDraft }),
  )
  assert.equal(assessed.status, 200)
  const assessment = (await assessed.json()).data
  assert.deepEqual(
    assessment.actions.find((a: { choice: { kind: string; phase?: string } }) =>
      unassigned
        ? a.choice.kind === 'phase' && a.choice.phase === entryPhase
        : a.choice.kind === 'keep',
    ).targets,
    { calories_kcal: expectedKcal, protein_g: expectedProtein },
  )
  if (unassigned)
    assert.deepEqual(
      assessment.actions.find((a: { choice: { kind: string } }) => a.choice.kind === 'keep')
        .targets,
      { calories_kcal: 1700, protein_g: 120 },
    )
  cases.push('actual_REGULAR_public_HTTP_assessment_uses_core_formula_without_preparing_or_writing')
  const unaccepted = await questionnaire.ASSESS(
    post({ kind: scope.kind, cycleId: scope.cycleId, input: { ...publicDraft, bodyFat: null } }),
  )
  assert.equal(unaccepted.status, 200)
  assert.equal((await unaccepted.json()).data.status, 'body_fat_confirmation_required')
  cases.push('actual_new_photo_reading_requires_explicit_public_acceptance')
  const callCount = calls.length
  const smuggled = await questionnaire.ASSESS(
    post({
      kind: scope.kind,
      cycleId: scope.cycleId,
      input: { ...publicDraft, bodyFat: evaluated.command.bodyFat },
    }),
  )
  assert.equal(smuggled.status, 422)
  assert.equal(calls.length, callCount)
  cases.push('public_private_source_or_mean_injection_refused_before_any_actual_RPC')
  const prepareRequest = {
    kind: scope.kind,
    cycleId: scope.cycleId,
    operationKey: uid(4210),
    input: publicInput,
  }
  const fullRoutes = createClinicalFullRoutes(
    {
      enabled: true,
      createService: () => service,
      createHealthDependencies: () => ({
        enabled: true,
        repository: createSupabaseHealthHoldRepository(client),
      }),
    },
    {
      authenticate: async () => auth,
      authorizeEntitlement: async () => {},
      createServiceClient: () => client,
      createRequestId: () => 'owned-full-command-qa',
    },
  )
  const { operationKey: _prepareKey, ...publicPrepare } = prepareRequest
  const previewResponse = await fullRoutes.PREVIEW(post(publicPrepare, prepareRequest.operationKey))
  assert.equal(previewResponse.status, 200)
  const publicPreview = (await previewResponse.json()).data
  assert.equal(publicPreview.status, 'ready')
  assert.deepEqual(publicPreview.targets, {
    calories_kcal: expectedKcal,
    protein_g: expectedProtein,
  })
  for (const key of [
    'beforeKcal',
    'beforeProtein',
    'context_hash',
    'sourceHash',
    'presentation',
    'user_id',
  ])
    assert(!JSON.stringify(publicPreview).includes(key))
  cases.push(
    'actual_public_PREVIEW_HTTP_uses_immutable_original_after_policy_and_never_exposes_private_packet',
  )
  const prepared = await repository.findPrepared(initial.user, {
    prepareOperationKey: prepareRequest.operationKey,
  })
  assert(prepared)
  assert.deepEqual(prepared.package, bundle)
  if (unassigned) {
    assert.deepEqual(await request({ type: 'phase_witness' }), beforePhase)
    assert.equal(prepared.command.form.phase, null)
  }
  const preview = prepared.preview.preview_id
  const confirmRequest = {
    kind: scope.kind,
    cycleId: scope.cycleId,
    previewId: preview,
    operationKey: uid(4211),
    input: publicInput,
  }
  assert.equal(await repository.findCommandReceipt(initial.user, preview, uid(4211)), null)
  cases.push('authenticated prepare calculates and atomically binds original command/package')
  const { operationKey: _confirmKey, ...publicConfirm } = confirmRequest
  const confirmResponse = await fullRoutes.CONFIRM(post(publicConfirm, confirmRequest.operationKey))
  assert.equal(confirmResponse.status, 200)
  const publicAck = (await confirmResponse.json()).data
  assert.equal(publicAck.review_id, preview)
  assert.equal(publicAck.kind, kind)
  for (const key of ['targets', 'body_fat_percent', 'safety_revision', 'user_id', 'presentation'])
    assert(!JSON.stringify(publicAck).includes(key))
  cases.push('actual_public_CONFIRM_HTTP_returns_historical_identity_calendar_only')
  const afterState = readCurrentClinicalState(
    await currentSource.capture({ userId: initial.user, mode: 'profile' }),
    initial.user,
  )
  assert.deepEqual(afterState.generation_authority, beforeState.generation_authority)
  assert.deepEqual(afterState.phase_origin, {
    kind: 'assigned',
    phase: unassigned ? entryPhase : 'recomposicao',
  })
  assert.equal(projectCurrentClinicalState(afterState).targetSource, 'assigned_phase')
  assert.equal(
    afterState.generation_token?.onboarding_completed_at,
    beforeState.generation_token?.onboarding_completed_at,
  )
  cases.push(
    'actual_current_source_refreshes_confirmed_FULL_phase_and_preserves_original_generation_marker',
  )
  if (unassigned) {
    const after = (await request({ type: 'phase_witness' })) as {
      phase: string
      old_marker_null: boolean
      signup_count: number
      first_phase_count: number
      FULL_count: number
      episode: object
    }
    assert.equal(after.phase, entryPhase)
    assert.equal(after.old_marker_null, true)
    assert.equal(after.signup_count, 0)
    assert.equal(after.first_phase_count, 0)
    assert.equal(after.FULL_count, 1)
    assert.deepEqual(after.episode, {
      source_review: true,
      source_first_phase: false,
      origin: 'confirmed_phase_change',
      difficulty: changedPhase ? null : 0,
      ledger: changedPhase ? [] : null,
    })
  }
  const afterEntryResponse = await entryRoutes.GET(
    new Request('https://bodyflow.test/api/mobile/v1/reevaluation'),
  )
  assert.equal(afterEntryResponse.status, 200)
  const afterEntry = (await afterEntryResponse.json()).data
  assert.equal(afterEntry.availability, 'unavailable')
  assert.equal(afterEntry.unavailable_reason, 'not_due')
  assert.equal(afterEntry.clock.due_date, publicAck.next_due_date)
  assert.equal(afterEntry.cycle, null)
  cases.push(
    'actual_post_confirmation_entry_uses_new_server_calendar_without_reopening_completed_cycle',
  )
  const found = await repository.findCommandReceipt(initial.user, preview, uid(4211))
  assert(found?.operation_matched)
  const original = {
    user_id: initial.user,
    preview_id: preview,
    operation_key: confirmRequest.operationKey,
    result: found.result,
  }
  assert.deepEqual(found.result, original.result)
  assert.equal(found.review_no, '1')
  cases.push('confirmed original packet/counter bindings')
  const routineScope = { userId: initial.user, kind: 'ROUTINE_REVIEW' as const, cycleId: null }
  const routineRaw = await repository.capture(routineScope)
  const routine = evaluateClinicalFull(routineRaw, routineScope, {
    form: {
      version: 1,
      phase: entryPhase,
      kind: 'ROUTINE_REVIEW',
      activityPurpose: 'normal',
      preference: null,
      answers: {
        weightKg: null,
        strengthSessions: 5,
        hunger: changedPhase ? 'moderada' : null,
        energy: null,
        adherence: null,
        strengthProgression: null,
        fatPerception: null,
        difficultToMaintain: null,
        activity: {
          otherExerciseType: null,
          otherExerciseDays: null,
          sessionMinutes: null,
          sessionIntensity: null,
          mostlySitting: null,
          activityLevel: 'alto',
          activityLevelConfirmed: true,
        },
        healthCheck: null,
        professionalConversationConfirmed: null,
      },
    },
    choice: { kind: 'activity' },
    measureConfirmed: false,
    bodyFat: null,
  })
  assert.equal(routine.package.proposal.targets.afterKcal, expectedRoutineKcal)
  assert.equal(routine.package.proposal.profile.training_frequency, 5)
  assert.equal(routine.package.proposal.profile.activity_level, 'alto')
  const routineInput = {
    activityPurpose: routine.command.form.activityPurpose,
    answers: routine.command.form.answers,
    preference: routine.command.form.preference,
    choice: routine.command.choice,
    measureConfirmed: routine.command.measureConfirmed,
    bodyFat: null,
  }
  const routinePreview = await service.preparePublic(auth, {
    kind: routineScope.kind,
    cycleId: null,
    operationKey: uid(4220),
    input: routineInput,
  })
  const routineAck = await service.confirmPublic(auth, {
    kind: routineScope.kind,
    cycleId: null,
    previewId: routinePreview.preview.preview_id,
    operationKey: uid(4221),
    input: routineInput,
  })
  assert.equal(routineAck.result.kind, 'ROUTINE_REVIEW')
  assert.equal(routineAck.result.cycle_id, null)
  assert.equal(routineAck.result.next_due_date, original.result.next_due_date)
  cases.push(
    'real routine activity/frequency package preserves recomposition calories and calendar',
  )
  const declared = await fullRoutes.DECLARE_HEALTH(post({ items: ['reduced_intake'] }, uid(4230)))
  assert.equal(declared.status, 200)
  const declaredPayload = (await declared.json()).data
  assert.equal(declaredPayload.version, 1)
  assert(declaredPayload.receipt_id)
  assert(!JSON.stringify(declaredPayload).includes('items'))
  cases.push(
    'actual_explicit_public_health_admission_HTTP_uses_existing_SQL_authority_and_projects_only_receipt',
  )
  await request({ type: 'reset' })
  const resetState = readCurrentClinicalState(
    await currentSource.capture({ userId: initial.user, mode: 'profile' }),
    initial.user,
  )
  assert.equal(resetState.generation_authority, undefined)
  assert.equal(resetState.signup_generation, null)
  assert.equal(resetState.generation_token?.onboarding_completed, false)
  assert.equal(resetState.phase_origin.kind, 'not_completed')
  cases.push(
    'actual_reset_invalidates_current_legacy_source_while_historical_FULL_remains_replayable',
  )
  const before = (await request({ type: 'witness' })) as {
    effects: string
    keys: { operation_key: string; review_id: string; input_hash: string }[]
  }
  const resetCalls = calls.length
  assert.deepEqual(await service.preparePublic(auth, prepareRequest), prepared)
  assert.deepEqual(await request({ type: 'witness' }), before)
  cases.push('actual reset then original prepare ACK without recapture or expiry extension')
  assert.deepEqual(await service.confirmPublic(auth, confirmRequest), original)
  assert.deepEqual(await request({ type: 'witness' }), before)
  cases.push('actual reset then original replay without effect resurrection')
  const alias = await repository.findCommandReceipt(initial.user, preview, uid(4212))
  assert(alias && !alias.operation_matched)
  const aliasAck = await service.confirmPublic(auth, { ...confirmRequest, operationKey: uid(4212) })
  assert(!calls.slice(resetCalls).includes('get_mobile_clinical_full_context'))
  assert.deepEqual(aliasAck.result, original.result)
  assert((await repository.findCommandReceipt(initial.user, preview, uid(4212)))?.operation_matched)
  const afterAlias = (await request({ type: 'witness' })) as typeof before
  assert.equal(afterAlias.effects, before.effects)
  assert.equal(before.keys.length, 2)
  assert.equal(afterAlias.keys.length, 3)
  assert.deepEqual(
    afterAlias.keys.filter((row) => row.operation_key !== uid(4212)),
    before.keys,
  )
  const aliasRow = afterAlias.keys.find((row) => row.operation_key === uid(4212))
  assert(aliasRow)
  assert.equal(aliasRow.review_id, preview)
  assert.equal(aliasRow.input_hash, before.keys[0]?.input_hash)
  cases.push('unmatched alias binds only original package before recapture')
  const changed = structuredClone(publicInput)
  changed.answers.weightKg = 83
  await assert.rejects(service.confirmPublic(auth, { ...confirmRequest, input: changed }), {
    status: 409,
    code: 'mobile_clinical_full_changed',
  })
  await assert.rejects(repository.findCommandReceipt(initial.user, uid(4213), uid(4211)), {
    status: 409,
    code: 'mobile_clinical_full_changed',
  })
  cases.push('same key rejects changed form and preview')
  assert.equal(await repository.findCommandReceipt(uid(4201), preview, uid(4211)), null)
  cases.push('cross-owner original receipt not visible')
  return {
    type: 'result',
    status: 'PASS_AUTHENTICATED_FULL_COMMAND_SERVICE_SQL',
    cases,
    initial_kind: kind,
  }
}
try {
  send(await run())
} catch (error) {
  send({ type: 'failure' })
  console.error(error)
  process.exitCode = 1
} finally {
  await iterator.return?.()
}
