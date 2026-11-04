import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { z } from 'zod'
import { createClinicalDailyEffect } from './clinical-daily-effect'
import { clinicalDailyRepositoryError } from './clinical-daily-service'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  type ConversationMealDayPorts,
  createConversationMealDayInitializer,
} from './conversation-meal-day'
import type { ClinicalReadAdmission } from './current-clinical-read-model'
import { currentClinicalError, readCurrentClinicalState } from './current-clinical-state'
import fullWire from './testing/clinical-full-wire.json'
import { currentOnboardingWire } from './testing/current-onboarding-fixture'
import { consentAuth, uid } from './testing/reevaluation-photo-consent-fixture'

function command(id = uid(6700)) {
  return bindConversationCommand(consentAuth.userId, `cmsg1:${id}`, {
    command_protocol: 'conversation.command.v1',
    command_id: id,
    kind: 'meal.report',
    source: { channel: 'text', text: 'Comi arroz 100g' },
  })
}
describe('new command clinical day initializer', () => {
  it.each([
    'eligible',
    'hold',
    'unproven',
  ] as const)('defaults to real current-state/daily repository for %s', async (kind) => {
    const context = JSON.parse(
      JSON.stringify(fullWire.context).replaceAll(fullWire.context.user_id, consentAuth.userId),
    ) as typeof fullWire.context
    Object.assign(context, { review_kind: 'APPLICATION', cycle_id: null })
    const state = currentOnboardingWire(kind === 'hold' ? 'hold' : 'healthy')
    if (kind === 'eligible') {
      Object.assign(context.facts.profile, { body_fat_percent: null, body_fat_measured_at: null })
      Object.assign(context.facts.protocol_authority, {
        body_fat_origin: null,
        signup_body_fat_origin: null,
        body_fat_candidate: null,
      })
      Object.assign(state.body, { body_fat_percent: null })
    }
    Object.assign(state, {
      epoch: context.facts.anchor.signup_epoch,
      signup_generation: context.facts.anchor.signup_generation,
      observed_at: context.observed_at,
      date: context.facts.calculation_date,
      generation_authority: context.facts.anchor.authority,
      generation_token: {
        ...state.generation_token,
        onboarding_completed_at: context.facts.anchor.authority.completed_at,
      },
    })
    Object.assign(state.safety, { observed_at: state.observed_at, date: state.date })
    Object.assign(context.facts.safety, state.health_state)
    const calls: { name: string; args: Record<string, unknown> }[] = [],
      receipts: unknown[] = []
    const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args })
      if (name === 'get_mobile_current_clinical_state') return { data: state, error: null }
      if (name === 'get_mobile_clinical_daily_receipt')
        return { data: receipts[0] ?? null, error: null }
      if (name === 'get_mobile_clinical_daily_context') return { data: context, error: null }
      if (name === 'apply_mobile_clinical_daily') {
        const result = {
          user_id: consentAuth.userId,
          operation_key: args.p_operation_key,
          result: {
            version: 1,
            availability: 'unavailable',
            reason: 'clinical_episode_unavailable',
            date: state.date,
          },
        }
        receipts.push(result)
        return { data: result, error: null }
      }
      throw new Error('forbidden closer/food/XP/source/model')
    })
    const initialize = createConversationMealDayInitializer({
      rpc,
    } as unknown as ServiceClient).initialize
    expect(calls).toEqual([])
    await initialize(consentAuth, command())
    await initialize(consentAuth, command())
    if (kind === 'unproven') {
      expect(calls.map((c) => c.name)).toEqual([
        'get_mobile_current_clinical_state',
        'get_mobile_clinical_daily_receipt',
        'get_mobile_clinical_daily_context',
        'get_mobile_current_clinical_state',
        'get_mobile_clinical_daily_receipt',
        'get_mobile_clinical_daily_context',
      ])
      return
    }
    expect(calls.map((c) => c.name)).toEqual([
      'get_mobile_current_clinical_state',
      'get_mobile_clinical_daily_receipt',
      'get_mobile_clinical_daily_context',
      'apply_mobile_clinical_daily',
      'get_mobile_current_clinical_state',
      'get_mobile_clinical_daily_receipt',
    ])
    if (kind === 'hold')
      expect(calls[3]?.args.p_calculation).toEqual({
        version: 1,
        formulaKcal: null,
        maintenanceKcal: null,
        sedentaryKcal: null,
        proteinTarget: null,
        maintenanceProteinTarget: null,
      })
    else
      expect(calls[3]?.args.p_calculation).toMatchObject({
        version: 1,
        formulaKcal: expect.any(Number),
        proteinTarget: expect.any(Number),
      })
    expect(calls[1]?.args.p_operation_key).toBe(calls[5]?.args.p_operation_key)
  })
  it('uses real preflight and legacy admission, preserving an unassigned phase without targets or closeDays', async () => {
    const before = currentOnboardingWire()
    before.phase_origin = { kind: 'legacy_unassigned' }
    const authority = {
      kind: 'legacy_transition',
      user_id: consentAuth.userId,
      generation: before.signup_generation,
      epoch: before.epoch,
      admitted_at: before.observed_at,
      admitted_date: before.date,
      timezone_at_admission: before.timezone,
      profile_completed_marker: before.generation_token.onboarding_completed_at,
    }
    const after = { ...before, generation_authority: authority }
    const calls: { name: string; args: unknown }[] = []
    const rpc = vi.fn(async (name: string, args: unknown) => {
      calls.push({ name, args })
      if (name === 'get_mobile_current_clinical_state')
        return {
          data: (args as { p_expected: unknown }).p_expected === null ? before : after,
          error: null,
        }
      if (name === 'admit_mobile_clinical_legacy_generation')
        return { data: { version: 1, availability: 'admitted', authority }, error: null }
      throw new Error('unexpected writer/closer/source/provider')
    })
    const initializer = createConversationMealDayInitializer({
      rpc,
    } as unknown as ServiceClient)
    expect(calls).toEqual([])
    await Promise.all([
      initializer.initialize(consentAuth, command()),
      initializer.initialize(consentAuth, command(uid(6701))),
    ])
    expect(calls.map((c) => c.name)).toEqual([
      'get_mobile_current_clinical_state',
      'get_mobile_current_clinical_state',
      'admit_mobile_clinical_legacy_generation',
      'admit_mobile_clinical_legacy_generation',
      'get_mobile_current_clinical_state',
      'get_mobile_current_clinical_state',
    ])
    expect(calls[0]?.args).toEqual({
      p_user_id: consentAuth.userId,
      p_mode: 'profile',
      p_body: null,
      p_expected: null,
    })
  })
})

function admission(kind: 'healthy' | 'hold' | 'no_plan' = 'healthy'): ClinicalReadAdmission {
  return {
    owner: consentAuth.userId,
    compatible: true,
    state: readCurrentClinicalState(currentOnboardingWire(kind), consentAuth.userId),
  }
}
function harness(
  raw = admission(),
  effectResult: unknown = {
    version: 1,
    availability: 'unavailable',
    reason: 'clinical_episode_unavailable',
    date: '2026-10-27',
  },
) {
  const calls: string[] = [],
    keys: string[] = [],
    scopes: unknown[] = []
  const preflight = vi.fn(
    async (
      ..._args: Parameters<ReturnType<ConversationMealDayPorts['createReadModel']>['preflight']>
    ) => raw,
  )
  const ports: ConversationMealDayPorts = {
    createReadModel() {
      calls.push('model')
      return {
        preflight: (...args) => {
          calls.push('preflight')
          return preflight(...args)
        },
      }
    },
    createDailyEffect(options) {
      calls.push('effect')
      return createClinicalDailyEffect({
        ...options,
        createService: () => ({
          apply: async (auth, input) => {
            calls.push('daily')
            keys.push(
              z.object({ operationKey: z.string().uuid() }).strict().parse(input).operationKey,
            )
            scopes.push(auth)
            return effectResult as Awaited<
              ReturnType<
                ReturnType<
                  typeof import('./clinical-daily-service').createClinicalDailyService
                >['apply']
              >
            >
          },
        }),
      })
    },
  }
  const db = {
    rpc() {
      throw new Error('unexpected RPC')
    },
  } as unknown as ServiceClient
  return {
    initializer: createConversationMealDayInitializer(db, ports),
    ports,
    preflight,
    calls,
    keys,
    scopes,
    db,
  }
}
describe('server daily operation binding', () => {
  it('uses one proper namespaced v5 identity for parallel same-command/date requests', async () => {
    const h = harness()
    expect(h.calls).toEqual([])
    await Promise.all([
      h.initializer.initialize(consentAuth, command()),
      h.initializer.initialize(consentAuth, command()),
    ])
    expect(h.keys).toEqual([
      '07e455a8-538e-542d-bbe4-aef458479c0e',
      '07e455a8-538e-542d-bbe4-aef458479c0e',
    ])
    expect(h.calls).toEqual([
      'model',
      'preflight',
      'model',
      'preflight',
      'effect',
      'daily',
      'effect',
      'daily',
    ])
    expect(h.preflight.mock.calls[0]).toEqual([
      expect.objectContaining({ userId: consentAuth.userId }),
      'https://conversation.invalid/api/mobile/v1/today?clinical_policy=current_clinical_v1',
      'today',
    ])
  })
  it('does not use a caller clock/URL/key and separates distinct commands and server civil dates', async () => {
    const h = harness(),
      next = structuredClone(admission())
    Object.assign(next.state, { date: '2026-10-28', observed_at: '2026-10-28T12:00:00.000001Z' })
    if (!next.state.safety) throw new Error('Complete fixture required')
    Object.assign(next.state.safety, { date: next.state.date, observed_at: next.state.observed_at })
    h.preflight
      .mockResolvedValueOnce(admission())
      .mockResolvedValueOnce(admission())
      .mockResolvedValueOnce(next)
    await h.initializer.initialize(consentAuth, command())
    await h.initializer.initialize(consentAuth, command(uid(6701)))
    await h.initializer.initialize(consentAuth, command())
    expect(new Set(h.keys).size).toBe(3)
    expect(h.keys[0]).toBe('07e455a8-538e-542d-bbe4-aef458479c0e')
  })
  it.each([
    'clinical_episode_unavailable',
    'day_closed',
    'schedule_not_started',
    'phase_not_started',
    'legacy_formula_origin_unproven',
    'protein_table_unverified',
    'calculation_unavailable',
  ])('preserves daily %s without inventing a target or fallback', async (reason) => {
    const h = harness(admission(), {
      version: 1,
      availability: 'unavailable',
      reason,
      date: '2026-10-27',
    })
    await expect(h.initializer.initialize(consentAuth, command())).resolves.toBeUndefined()
    expect(h.calls).toEqual(['model', 'preflight', 'effect', 'daily'])
  })
  it('keeps assigned HOLD on the real daily effect path', async () => {
    const h = harness(admission('hold'))
    await h.initializer.initialize(consentAuth, command())
    expect(h.keys).toEqual(['07e455a8-538e-542d-bbe4-aef458479c0e'])
  })
  it.each([
    'legacy_unassigned',
    'confirmed_no_plan',
  ])('does not apply daily targets for %s', async (kind) => {
    const raw = structuredClone(admission())
    Object.assign(raw.state, {
      phase_origin:
        kind === 'legacy_unassigned'
          ? { kind }
          : {
              kind,
              signupGeneration: raw.state.signup_generation,
              signupEpoch: raw.state.epoch,
              completedAt: raw.state.generation_token?.onboarding_completed_at,
            },
    })
    const h = harness(raw)
    await h.initializer.initialize(consentAuth, command())
    expect(h.keys).toEqual([])
    expect(h.calls).toEqual(['model', 'preflight', 'effect'])
  })
  it.each([
    'patient',
    'identity',
    'owner',
    'hash',
    'source',
  ])('rejects %s mismatch before any preflight or effect', async (field) => {
    const h = harness(),
      auth = structuredClone(consentAuth),
      bound = structuredClone(command())
    if (field === 'patient') auth.patient.id = uid(9999)
    if (field === 'identity') auth.identity.id = uid(9999)
    if (field === 'owner')
      Object.assign(
        bound,
        bindConversationCommand(uid(9999), `cmsg1:${bound.commandId}`, bound.command),
      )
    if (field === 'hash') Object.assign(bound, { inputHash: 'f'.repeat(64) })
    if (field === 'source') Object.assign(bound.command.source, { text: 'Alterado' })
    await expect(h.initializer.initialize(auth, bound)).rejects.toBeDefined()
    expect(h.calls).toEqual([])
  })
  it.each([
    'owner',
    'compatible',
    'state',
  ])('rejects foreign/invalid preflight %s before daily', async (field) => {
    const raw = structuredClone(admission())
    if (field === 'owner') Object.assign(raw, { owner: uid(9999) })
    if (field === 'compatible') Object.assign(raw, { compatible: false })
    if (field === 'state') Object.assign(raw.state, { user_id: uid(9999) })
    const h = harness(raw)
    await expect(h.initializer.initialize(consentAuth, command())).rejects.toMatchObject({
      code: 'mobile_current_clinical_invalid_response',
    })
    expect(h.calls).toEqual(['model', 'preflight'])
  })
  it.each([
    'unavailable',
    'changed',
    'busy',
  ] as const)('keeps profile %s errors and never applies daily', async (kind) => {
    const h = harness()
    h.preflight.mockRejectedValueOnce(currentClinicalError(kind))
    await expect(h.initializer.initialize(consentAuth, command())).rejects.toMatchObject({
      code: `mobile_current_clinical_${kind}`,
    })
    expect(h.calls).toEqual(['model', 'preflight'])
  })
  it('preserves a body-changed daily conflict without another call', async () => {
    const original = harness(admission())
    const custom = createConversationMealDayInitializer(original.db, {
      createReadModel: () => ({ preflight: async () => admission() }),
      createDailyEffect: () => async () => {
        throw clinicalDailyRepositoryError('changed')
      },
    })
    await expect(custom.initialize(consentAuth, command())).rejects.toMatchObject({
      status: 409,
      code: 'mobile_clinical_daily_changed',
    })
  })
  it('redacts arbitrary callback failures instead of leaking raw backend details', async () => {
    const h = harness()
    h.preflight.mockRejectedValueOnce(new Error('private SQL URL token'))
    await expect(h.initializer.initialize(consentAuth, command())).rejects.toMatchObject({
      status: 503,
      code: 'conversation_meal_day_unavailable',
      message: 'Meal day initialization is unavailable',
    })
    expect(h.keys).toEqual([])
  })
  it('captures auth, whole command and configured callbacks before the first await', async () => {
    const h = harness(),
      raw = structuredClone(admission()),
      auth = structuredClone(consentAuth),
      bound = structuredClone(command())
    let release: (v: ClinicalReadAdmission) => void = () => {}
    h.preflight.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          release = resolve
        }),
    )
    const pending = h.initializer.initialize(auth, bound)
    auth.patient.id = uid(9999)
    Object.assign(bound, { commandId: uid(9999) })
    h.ports.createReadModel = () => {
      throw new Error('late model')
    }
    h.ports.createDailyEffect = () => {
      throw new Error('late effect')
    }
    release(raw)
    await pending
    Object.assign(raw.state, { date: '2026-10-29' })
    expect(h.keys).toEqual(['07e455a8-538e-542d-bbe4-aef458479c0e'])
    expect(h.scopes).toEqual([consentAuth])
    expect(Object.isFrozen(h.scopes[0])).toBe(true)
  })
  it('detaches the preflight observation before invoking another configured callback', async () => {
    const raw = structuredClone(admission()),
      seen: ClinicalReadAdmission[] = []
    const initializer = createConversationMealDayInitializer({} as ServiceClient, {
      createReadModel: () => ({ preflight: async () => raw }),
      createDailyEffect: () => {
        Object.assign(raw.state.body, { weight_kg: 99 })
        return async (scope) => {
          seen.push(scope.admission)
        }
      },
    })
    await initializer.initialize(consentAuth, command())
    expect(seen[0]?.state.body.weight_kg).toBe(80)
    expect(Object.isFrozen(seen[0]?.state.body)).toBe(true)
  })
})
