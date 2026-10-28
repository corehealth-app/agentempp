/** Actual daily service/core/public SQL over genuine synthetic signup records.
 * Parent owns one ROLLBACK transaction. No fabricated FULL/photo/provider. */
import assert from 'node:assert/strict'
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from '../../../apps/admin/src/lib/mobile-api/auth'
import { createClinicalDailyService } from '../../../apps/admin/src/lib/mobile-api/clinical-daily-service'
import { createClinicalFullService } from '../../../apps/admin/src/lib/mobile-api/clinical-full-service'
import { calculateClinicalSnapshotTargets } from '../../../apps/admin/src/lib/mobile-api/clinical-snapshot-calculation'
import { createSupabaseClinicalDailyRepository } from '../../../apps/admin/src/lib/mobile-api/supabase-clinical-daily'
import { createSupabaseClinicalFullRepository } from '../../../apps/admin/src/lib/mobile-api/supabase-clinical-full'

if (process.env.PERFORME_SIGNUP_TARGET_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw new Error('Owned parent required')
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
type State = {
  hash: string
  day: Record<string, unknown> | null
  origin: { source: string; signup_application_id: string; calories_target: number } | null
  fulls: number
  events: number
  applications: number
  origins: number
  prior_hash: string | null
}
async function run() {
  const repository = createSupabaseClinicalDailyRepository({
    rpc: (name: string, args: Record<string, unknown>) => request({ type: 'rpc', name, args }),
  } as unknown as ServiceClient)
  const service = createClinicalDailyService({ enabled: true, repository })
  const results: string[] = []
  const full = createClinicalFullService({
    enabled: true,
    repository: createSupabaseClinicalFullRepository({
      rpc: (name: string, args: Record<string, unknown>) => request({ type: 'rpc', name, args }),
    } as unknown as ServiceClient),
  })
  const cases = [
    'recomposicao',
    'manutencao',
    'ganho_massa',
    'first_EARLY',
    'HOLD',
    'no_plan',
    'unknown_current',
    'unknown_prior',
    'closed',
  ]
  for (const [index, name] of cases.entries()) {
    const seeded = (await request({ type: 'seed', case: name })) as {
      user: string
      generation: string
    }
    const auth: MobileAuthContext = {
      userId: seeded.user,
      authUserId: uid(6399),
      accessToken: 'synthetic-session',
      identity: { id: uid(6399), email: null, emailConfirmedAt: null },
      patient: {
        id: seeded.user,
        authUserId: uid(6399),
        email: null,
        name: null,
        locale: 'pt-BR',
        timezone: 'Etc/GMT+12',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    }
    const before = (await request({ type: 'state' })) as State
    const command = { operationKey: uid(6500 + index) }
    if (name === 'no_plan') {
      await assert.rejects(service.apply(auth, command), { status: 503 })
      assert.deepEqual(await request({ type: 'state' }), before)
      results.push(`${name}: absent phase never manufactures target`)
      continue
    }
    if (name === 'unknown_current' || name === 'closed') {
      const refused = await service.apply(auth, command)
      assert.equal(refused.availability, 'unavailable')
      assert.equal(refused.reason, 'legacy_formula_origin_unproven')
      assert.deepEqual(await request({ type: 'state' }), before)
      results.push(`${name}: existing unknown numbers and closed row exact`)
      continue
    }
    let previous: string | null = null
    if (name === 'unknown_prior')
      previous = ((await request({ type: 'advance' })) as { prior_hash: string }).prior_hash
    const capture = await repository.capture(seeded.user)
    const calculated = calculateClinicalSnapshotTargets(capture, seeded.user)
    assert.equal(calculated.formulaBodyFatPercent, null)
    const result = await service.apply(auth, command)
    assert.equal(result.availability, 'applied')
    if (result.availability !== 'applied') throw new Error('Expected applied')
    assert.equal(result.source_kind, 'signup')
    assert.equal(result.source_review_id, null)
    assert.equal(result.source_signup_id, seeded.generation)
    const actual = (await request({ type: 'state' })) as State
    assert.equal(actual.fulls, 0)
    assert.equal(actual.events, 0)
    if (name === 'HOLD') {
      assert.equal(actual.day, null)
      assert.equal(actual.origin, null)
      assert.equal(result.reason, 'safety')
      assert.equal(result.targets.calories_target, null)
    } else if (name === 'unknown_prior') {
      assert.equal(result.reason, 'signup_preserved_unknown')
      assert.equal(result.targets.formula_target, null)
      assert.equal(actual.day?.calories_target, 1099)
      assert.equal(actual.origin, null)
      assert.equal(actual.prior_hash, previous)
    } else {
      assert.equal(actual.day?.calories_target, calculated.formulaKcal)
      assert.equal(actual.day?.protein_target, calculated.proteinTarget)
      assert.equal(actual.origin?.source, 'clinical_signup_v1')
      assert.equal(actual.origin?.signup_application_id, result.application_id)
    }
    assert.deepEqual(await service.apply(auth, command), result)
    assert.deepEqual(await request({ type: 'state' }), actual)
    if (name === 'first_EARLY') {
      const early = (await request({ type: 'early' })) as { cycle: { id: string } }
      const input = {
        choice: { kind: 'keep' },
        measureConfirmed: false,
        bodyFat: null,
        form: {
          version: 1,
          phase: 'recomposicao',
          kind: 'EARLY_FULL',
          activityPurpose: 'normal',
          preference: null,
          answers: {
            weightKg: 80,
            strengthSessions: 4,
            hunger: 'moderada',
            energy: 'boa',
            adherence: 'bem_consistente',
            strengthProgression: null,
            fatPerception: null,
            difficultToMaintain: null,
            activity: null,
            healthCheck: { kind: 'none' },
            professionalConversationConfirmed: null,
          },
        },
      }
      const preview = await full.prepare(auth, {
        kind: 'EARLY_FULL',
        cycleId: early.cycle.id,
        operationKey: uid(6700 + index),
        input,
      })
      assert.equal(preview.package.proposal.episode.difficultyCount, 0)
      const confirm = {
        kind: 'EARLY_FULL',
        cycleId: early.cycle.id,
        previewId: preview.preview.preview_id,
        operationKey: uid(6800 + index),
        input,
      }
      const ack = await full.confirm(auth, confirm)
      const after = (await request({ type: 'state' })) as State
      assert.equal(after.fulls, 1)
      assert.equal(after.events, 1)
      assert.equal(after.origin?.source, 'clinical_full_v1')
      assert.deepEqual(await full.confirm(auth, confirm), ack)
      assert.deepEqual(await service.apply(auth, command), result)
      assert.deepEqual(await request({ type: 'state' }), after)
    }
    if (['recomposicao', 'manutencao', 'ganho_massa'].includes(name)) {
      const advanced = (await request({ type: 'advance' })) as { prior_hash: string }
      const nextSnapshot = await repository.capture(seeded.user)
      const nextCalculation = calculateClinicalSnapshotTargets(nextSnapshot, seeded.user)
      const next = await service.apply(auth, { operationKey: uid(6600 + index) })
      assert.equal(next.availability, 'applied')
      const nextState = (await request({ type: 'state' })) as State
      assert.equal(nextState.fulls, 0)
      assert.equal(nextState.events, 0)
      assert.equal(nextState.prior_hash, advanced.prior_hash)
      assert.equal(nextState.day?.calories_target, nextCalculation.formulaKcal)
      assert.equal(nextState.origin?.source, 'clinical_signup_v1')
      assert.equal(nextState.applications, 2)
      assert.equal(nextState.origins, 2)
      assert.deepEqual(await service.apply(auth, command), result)
      assert.deepEqual(await request({ type: 'state' }), nextState)
      await request({ type: 'reset' })
      const reset = (await request({ type: 'state' })) as State
      assert.deepEqual(await service.apply(auth, command), result)
      assert.deepEqual(await request({ type: 'state' }), reset)
    }
    results.push(`${name}: actual service/core/public SQL, source binding, preservation and replay`)
  }
  return { type: 'result', status: 'PASS_ACTUAL_ASSIGNED_SIGNUP_DAILY_SQL', cases: results }
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
