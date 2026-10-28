/** All-phase CURRENT service/writer proof over explicit synthetic old signup
 * fixtures. Does not prove historical signup emission, provider or Storage. */
import assert from 'node:assert/strict'
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from '../../../apps/admin/src/lib/mobile-api/auth'
import { createClinicalDailyService } from '../../../apps/admin/src/lib/mobile-api/clinical-daily-service'
import { readClinicalFullContext } from '../../../apps/admin/src/lib/mobile-api/clinical-full-authority'
import { createClinicalFullService } from '../../../apps/admin/src/lib/mobile-api/clinical-full-service'
import { calculateClinicalSnapshotTargets } from '../../../apps/admin/src/lib/mobile-api/clinical-snapshot-calculation'
import { createSupabaseClinicalDailyRepository } from '../../../apps/admin/src/lib/mobile-api/supabase-clinical-daily'
import { createSupabaseClinicalFullRepository } from '../../../apps/admin/src/lib/mobile-api/supabase-clinical-full'

if (process.env.PERFORME_CLINICAL_PHASE_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw new Error('Owned rollback parent required')
const iterator = createInterface({ input: process.stdin, crlfDelay: Infinity })[
  Symbol.asyncIterator
]()
const send = (v: unknown) => process.stdout.write(`${JSON.stringify(v)}\n`)
async function request(v: object): Promise<unknown> {
  send(v)
  const r = await iterator.next()
  if (r.done) throw new Error('Parent closed')
  return JSON.parse(r.value)
}
const uid = (n: number) => `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`
const activity = {
  otherExerciseType: null,
  otherExerciseDays: null,
  sessionMinutes: null,
  sessionIntensity: null,
  mostlySitting: null,
  activityLevel: 'moderado',
  activityLevelConfirmed: true,
}
type State = {
  origin: {
    source: string
    review_id: string | null
    application_id: string | null
    origin_kind: string
    calories_target: number
    protein_target: number
  } | null
  origin_hash: string
  prior_hash: string | null
  decisions_hash: string
  phase: string
  deficit_level: number | null
  day: Record<string, unknown> | null
  episode: {
    phase: string
    deficit_level: number | null
    ledger_steps: number[] | null
    maintenance_since: string | null
    difficulty_count: string | null
    schedule: { kind: string; state: string } | null
  } | null
  fulls: number
  keys: number
  weights: number
  clock: { base_date: string; due_date: string }
}
async function run() {
  const repository = createSupabaseClinicalFullRepository({
    rpc: (name: string, args: Record<string, unknown>) => request({ type: 'rpc', name, args }),
  } as unknown as ServiceClient)
  const service = createClinicalFullService({ enabled: true, repository })
  const dailyRepository = createSupabaseClinicalDailyRepository({
    rpc: (name: string, args: Record<string, unknown>) => request({ type: 'rpc', name, args }),
  } as unknown as ServiceClient)
  const daily = createClinicalDailyService({ enabled: true, repository: dailyRepository })
  const cases: string[] = []
  const names = [
    'recomp_transition',
    'maintenance_recomp',
    'maintenance_step',
    'gain_step',
    'gain_exit',
    'gain_exit_complete',
    'guarded_keep',
    'closed_transition',
    'gain_without_history',
    'direct_recomp_gain',
    'direct_gain_recomp',
    'maintenance_gain',
    'maintenance_recomp_choice',
    'gain_sparse_history',
    'missing_day',
    'null_target',
    'legacy_null_guard',
  ]
  for (const [index, name] of names.entries()) {
    const seeded = (await request({ type: 'seed', case: name })) as { user: string; cycle: string }
    const auth: MobileAuthContext = {
      userId: seeded.user,
      authUserId: uid(4599),
      accessToken: 'synthetic-session',
      identity: { id: uid(4599), email: null, emailConfirmedAt: null },
      patient: {
        id: seeded.user,
        authUserId: uid(4599),
        email: null,
        name: null,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    }
    const scope = { userId: seeded.user, kind: 'REGULAR' as const, cycleId: seeded.cycle }
    const context = readClinicalFullContext(await repository.capture(scope), scope)
    const phase = context.facts.profile.current_protocol
    assert(phase)
    if (name === 'legacy_null_guard')
      assert.equal(context.facts.protocol_authority.signup_origin, null)
    else assert.equal(context.facts.protocol_authority.signup_origin?.phase, phase)
    const photo = context.facts.protocol_authority.body_fat_candidate
    assert(photo?.availability === 'available')
    const transition = name === 'recomp_transition' || name === 'closed_transition'
    const step = name === 'maintenance_step' || name === 'gain_step'
    const destination =
      transition || name.startsWith('gain_exit')
        ? 'manutencao'
        : name === 'maintenance_recomp' ||
            name === 'maintenance_recomp_choice' ||
            name === 'direct_gain_recomp'
          ? 'recomposicao'
          : 'ganho_massa'
    const choice = ['guarded_keep', 'legacy_null_guard', 'missing_day', 'null_target'].includes(
      name,
    )
      ? { kind: 'keep' as const }
      : step
        ? { kind: 'phase_calorie_step' as const }
        : {
            kind: 'phase' as const,
            phase: destination as 'manutencao' | 'recomposicao' | 'ganho_massa',
          }
    const input = {
      choice,
      measureConfirmed: name === 'maintenance_recomp',
      bodyFat: {
        confirmed: true,
        sourceHash: photo.source_hash,
        meanHundredths: photo.mean_hundredths,
      },
      form: {
        version: 1,
        phase,
        kind: 'REGULAR',
        activityPurpose:
          transition || name === 'direct_recomp_gain' ? 'consider_maintenance' : 'normal',
        preference: null,
        answers: {
          weightKg: 80,
          strengthSessions: 4,
          adherence: 'bem_consistente',
          hunger: step ? 'muita' : 'moderada',
          energy: step ? 'baixa' : 'boa',
          strengthProgression: phase === 'ganho_massa' ? 'piorou_ou_travou' : null,
          fatPerception: phase === 'ganho_massa' ? 'nao_percebi' : null,
          difficultToMaintain: phase === 'manutencao' ? 'nao' : null,
          activity: choice.kind === 'phase' ? activity : null,
          healthCheck: { kind: 'none' },
          professionalConversationConfirmed: null,
        },
      },
    }
    const before = (await request({ type: 'state' })) as State
    const prepareRequest = {
      kind: 'REGULAR',
      cycleId: seeded.cycle,
      operationKey: uid(4600 + index),
      input,
    }
    if (
      name === 'gain_without_history' ||
      name === 'gain_sparse_history' ||
      name.startsWith('direct_')
    ) {
      await assert.rejects(service.prepare(auth, prepareRequest), { status: 409 })
      assert.deepEqual(await request({ type: 'state' }), before)
      cases.push(`${name}: refused without writer effects`)
      continue
    }
    const prepared = await service.prepare(auth, prepareRequest)
    const p = prepared.package.proposal
    if (transition) {
      assert.equal(p.principal, 'recomposition_transition')
      assert.equal(p.profile.current_protocol, 'manutencao')
      assert.equal(p.targets.afterKcal, 1800)
      assert.equal(p.episode.maintenanceSince, null)
      assert.equal(p.episode.schedule?.kind, 'recomp_to_maintenance')
    } else if (name === 'maintenance_recomp' || name === 'maintenance_recomp_choice') {
      assert.equal(p.principal, 'phase_recomposition')
      assert.equal(p.profile.deficit_level, 500)
    } else if (name === 'maintenance_gain') {
      assert.equal(p.principal, 'phase_gain')
      assert.equal(p.profile.current_protocol, 'ganho_massa')
      assert.equal(p.profile.deficit_level, null)
      assert.deepEqual(p.episode.ledgerSteps, [])
      assert.equal(p.episode.maintenanceSince, null)
    } else if (step) {
      assert.equal(p.principal, name === 'maintenance_step' ? 'maintenance_step' : 'gain_step')
      assert(p.targets.afterKcal && p.targets.formulaAfterKcal)
      assert.equal(
        p.targets.afterKcal - p.targets.formulaAfterKcal,
        name === 'maintenance_step' ? 100 : 150,
      )
    } else if (name.startsWith('gain_exit')) {
      assert.equal(p.principal, 'gain_exit')
      assert(p.episode.schedule)
      assert.equal(
        p.targets.afterKcal,
        Math.max(
          p.episode.schedule.maintenanceTargetKcal,
          Number(before.day?.calories_target) - 100,
        ),
      )
      assert.equal(
        p.profile.current_protocol,
        name === 'gain_exit_complete' ? 'manutencao' : 'ganho_massa',
      )
      if (name === 'gain_exit_complete') {
        assert.deepEqual(p.episode.ledgerSteps, [])
        assert.equal(p.episode.maintenanceSince, context.facts.calculation_date)
      }
    } else if (name === 'guarded_keep' || name === 'legacy_null_guard') {
      assert.equal(p.principal, 'keep')
      assert.equal(p.targets.afterKcal, 1700)
      assert.equal(p.targets.afterProtein, 144)
      assert.equal(p.targets.formulaAfterKcal, null)
      if (name === 'legacy_null_guard') {
        assert.equal(p.profile.deficit_level, null)
        assert.equal(p.episode.difficultyCount, null)
      }
    } else {
      assert.equal(p.principal, 'keep')
      assert(p.targets.afterKcal && p.targets.formulaAfterKcal)
      assert.equal(p.targets.beforeKcal, null)
    }
    const confirmRequest = {
      kind: 'REGULAR',
      cycleId: seeded.cycle,
      previewId: prepared.preview.preview_id,
      operationKey: uid(4700 + index),
      input,
    }
    const result = await service.confirm(auth, confirmRequest)
    const after = (await request({ type: 'state' })) as State
    assert.equal(result.result.principal, p.principal)
    assert.equal(after.fulls, before.fulls + 1)
    assert.equal(after.keys, before.keys + 1)
    assert.equal(after.phase, p.profile.current_protocol)
    assert.equal(after.deficit_level, p.profile.deficit_level)
    assert.equal(after.weights, before.weights + 1)
    assert.equal(after.episode?.phase, p.profile.current_protocol)
    assert.deepEqual(after.episode?.ledger_steps, p.episode.ledgerSteps)
    assert.equal(after.episode?.maintenance_since, p.episode.maintenanceSince)
    if (name === 'closed_transition') assert.deepEqual(after.day, before.day)
    else {
      assert(after.day)
      assert.equal(after.day.calories_target, p.targets.afterKcal)
      assert.equal(after.day.protein_target, p.targets.afterProtein)
      assert.equal(after.day.calories_consumed, name === 'missing_day' ? 0 : 200)
      assert.equal(after.day.exercise_calories, name === 'missing_day' ? 0 : 50)
    }
    if (name === 'guarded_keep' || name === 'closed_transition' || name === 'legacy_null_guard')
      assert.equal(after.origin, null)
    else {
      assert(after.origin)
      assert.equal(after.origin.source, 'clinical_full_v1')
      assert.equal(after.origin.review_id, result.result.review_id)
      assert.equal(after.origin.calories_target, p.targets.afterKcal)
      assert.equal(after.origin.protein_target, p.targets.afterProtein)
    }
    assert.deepEqual(await service.confirm(auth, confirmRequest), result)
    assert.deepEqual(await request({ type: 'state' }), after)
    if (name === 'missing_day' || name === 'closed_transition') {
      const advanced = (await request({ type: 'prospective', action: 'advance' })) as {
        prior_hash: string
      }
      const nextSnapshot = await dailyRepository.capture(seeded.user)
      const projected = calculateClinicalSnapshotTargets(nextSnapshot, seeded.user)
      assert.equal(projected.storedTargets, null)
      assert.equal(projected.automaticCalculationReady, true)
      if (name === 'missing_day') {
        assert.equal(projected.bodyFat.origin, 'report')
        assert.equal(projected.formulaBodyFatPercent, null)
      }
      const nextCommand = { operationKey: uid(5600 + index) }
      const next = await daily.apply(auth, nextCommand)
      assert.equal(next.availability, 'applied')
      const actual = (await request({ type: 'state' })) as State
      assert.equal(actual.prior_hash, advanced.prior_hash)
      assert.equal(actual.origin?.source, 'clinical_daily_v1')
      assert.equal(actual.origin?.origin_kind, name === 'missing_day' ? 'calculated' : 'confirmed')
      assert.equal(actual.origin?.review_id, null)
      assert(actual.origin?.application_id)
      assert.equal(
        actual.day?.calories_target,
        name === 'closed_transition' ? 1800 : projected.formulaKcal,
      )
      if (name === 'closed_transition') {
        assert.equal(actual.episode?.maintenance_since, null)
        assert.equal(actual.episode?.schedule?.state, 'running')
      }
      assert.deepEqual(await daily.apply(auth, nextCommand), next)
      assert.deepEqual(await request({ type: 'state' }), actual)
      if (name === 'missing_day') {
        await request({ type: 'prospective', action: 'unknown_existing' })
        const unknown = (await request({ type: 'state' })) as State
        assert.equal(unknown.day?.calories_target, 1099)
        assert.equal(unknown.origin, null)
        const refused = await daily.apply(auth, { operationKey: uid(5700 + index) })
        assert.equal(refused.availability, 'unavailable')
        assert.equal(refused.reason, 'legacy_formula_origin_unproven')
        assert.deepEqual(await request({ type: 'state' }), unknown)
        assert.deepEqual(await daily.apply(auth, nextCommand), next)
        assert.deepEqual(await request({ type: 'state' }), unknown)
        const earlyCycle = (await request({ type: 'prospective', action: 'early_cycle' })) as {
          cycle: { id: string }
        }
        const beforeEarly = (await request({ type: 'state' })) as State
        const earlyInput = {
          ...input,
          bodyFat: null,
          form: { ...input.form, kind: 'EARLY_FULL' },
        }
        const earlyPrepared = await service.prepare(auth, {
          kind: 'EARLY_FULL',
          cycleId: earlyCycle.cycle.id,
          operationKey: uid(5800 + index),
          input: earlyInput,
        })
        const proposal = earlyPrepared.package.proposal
        assert.equal(proposal.targets.beforeKcal, 1099)
        assert.equal(proposal.targets.afterKcal, projected.formulaKcal)
        // Preparation inserts only its draft preview + normalized command.
        // Every other owner row, including the current target, stays exact.
        const { effects_hash: beforeDraft, ...beforeClinical } = beforeEarly as State & {
          effects_hash: string
        }
        const { effects_hash: afterDraft, ...afterClinical } = (await request({
          type: 'state',
        })) as State & { effects_hash: string }
        assert.notEqual(afterDraft, beforeDraft)
        assert.deepEqual(afterClinical, beforeClinical)
        const earlyCommand = {
          kind: 'EARLY_FULL',
          cycleId: earlyCycle.cycle.id,
          previewId: earlyPrepared.preview.preview_id,
          operationKey: uid(5900 + index),
          input: earlyInput,
        }
        const confirmed = await service.confirm(auth, earlyCommand)
        const updated = (await request({ type: 'state' })) as State
        assert.equal(updated.prior_hash, advanced.prior_hash)
        assert.equal(updated.day?.calories_target, proposal.targets.afterKcal)
        assert.equal(updated.origin?.source, 'clinical_full_v1')
        assert.equal(updated.origin?.review_id, confirmed.result.review_id)
        assert.deepEqual(await service.confirm(auth, earlyCommand), confirmed)
        assert.deepEqual(await request({ type: 'state' }), updated)
      }
    }
    if (name === 'legacy_null_guard') {
      const routineInput = {
        ...input,
        bodyFat: null,
        form: {
          ...input.form,
          kind: 'ROUTINE_REVIEW',
          answers: {
            ...input.form.answers,
            weightKg: null,
            hunger: null,
            energy: null,
            adherence: null,
            healthCheck: null,
            professionalConversationConfirmed: null,
          },
        },
      }
      const preparedRoutine = await service.prepare(auth, {
        kind: 'ROUTINE_REVIEW',
        cycleId: null,
        operationKey: uid(4900 + index),
        input: routineInput,
      })
      assert.equal(preparedRoutine.package.proposal.profile.deficit_level, null)
      const routineCommand = {
        kind: 'ROUTINE_REVIEW',
        cycleId: null,
        previewId: preparedRoutine.preview.preview_id,
        operationKey: uid(5000 + index),
        input: routineInput,
      }
      const routine = await service.confirm(auth, routineCommand)
      assert.deepEqual(await service.confirm(auth, routineCommand), routine)
      const dailyCommand = { operationKey: uid(5100 + index) }
      const applied = await daily.apply(auth, dailyCommand)
      assert.equal(applied.availability, 'applied')
      const latest = (await request({ type: 'state' })) as State
      assert.equal(latest.deficit_level, null)
      assert.equal(latest.episode?.deficit_level, null)
      assert.equal(latest.day?.calories_target, 1700)
      assert.equal(latest.origin, null)
      assert.deepEqual(await daily.apply(auth, dailyCommand), applied)
      assert.deepEqual(await request({ type: 'state' }), latest)
    }
    cases.push(`${name}: actual service/calculation/public SQL effects and replay`)
  }
  return { type: 'result', status: 'PASS_CURRENT_ALL_PHASE_SERVICE_SQL', cases }
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
