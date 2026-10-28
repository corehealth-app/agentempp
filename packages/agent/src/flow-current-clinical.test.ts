import { buildDailyState } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  bindMobileFlowClinicalPort,
  type FlowClinicalRead,
  flowClinicalFacts,
  flowClinicalPreferences,
  flowClinicalProposalAllowed,
  type MobileFlowClinicalPort,
} from './flow-current-clinical.js'
import type { ToolContext } from './tools/types.js'
import {
  consultaMetricas,
  consultaProgresso,
  consultaResumoPeriodo,
  propoePlanoDieta,
  propoePlanoTreino,
} from './tools.js'

function read(): FlowClinicalRead {
  const today = buildDailyState({
    localDate: '2026-10-27',
    generatedAt: '2026-10-27T12:00:00Z',
    protocol: 'recomposicao',
    calculatedTargets: { calories_target: null, protein_target: null },
    snapshot: null,
    meals: [],
    workouts: [],
    pendingRegistrations: [],
    hydrationTarget: null,
    routineItems: [],
    progress: null,
    mealGap: {
      expected: [],
      registered: [],
      skipped: [],
      open: [],
      reliable: false,
      activeDays: 0,
    },
  })
  return {
    version: 1,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    policy: {
      version: 1,
      observed_at: '2026-10-27T12:00:00Z',
      assessment: 'complete',
      recording_allowed: true,
      pause_weight_loss_guidance: true,
      professional_assessment_recommended: true,
      phase_selection_pending: false,
      target_source: 'unavailable',
      hide: { objective: true, calories: true, protein: true, balance: true, block: true },
    },
    today: { ...today, current_protocol: null, protocol: null },
    profile: {
      name: 'QA',
      sex: 'masculino',
      age: 36,
      weight_kg: 80,
      height_cm: 180,
      protocol: null,
      bf_percent: null,
    },
    progress: {
      xp_total: 125,
      level: 2,
      current_streak: 3,
      longest_streak: 4,
      blocks_completed: null,
      deficit_block: null,
      badges_earned: [],
    },
  }
}
function setup(withDrafts = false) {
  const facts = read(),
    revalidate = vi.fn(async () => {}),
    source = vi.fn(async () => facts),
    period = vi.fn(async () => ({
      periodo: 'semana' as const,
      from: '2026-10-21',
      to: '2026-10-27',
      clinical_policy: facts.policy,
      days: 2,
      avgConsumed: 1000,
      avgProtein: 55,
      avgNetBalance: null,
      completeDays: 2,
      adherencePct: 100,
    }))
  const lookup = vi.fn(async () => {
    throw new Error('Restricted draft lookup forbidden')
  })
  const create = vi.fn(async () => {
    throw new Error('Restricted draft creation forbidden')
  })
  const port: MobileFlowClinicalPort = {
    read: source,
    period,
    revalidate,
    ...(withDrafts ? { drafts: { lookup, create } } : {}),
  }
  const from = vi.fn(() => {
    throw new Error('Legacy read forbidden')
  })
  const ctx: ToolContext = {
    supabase: { from } as unknown as ServiceClient,
    userId: 'qa',
    userWpp: '',
    assistantIdentity: 'flow',
    flowClinical: bindMobileFlowClinicalPort(port),
    providerMessageId: 'turn',
    llm: {},
  }
  return {
    facts,
    revalidate,
    source,
    period,
    port,
    from,
    ctx,
    bound: ctx.flowClinical as MobileFlowClinicalPort,
    lookup,
    create,
  }
}
describe('mobile current clinical port', () => {
  it('binds callbacks before awaits and detaches producer aliases', async () => {
    const s = setup()
    const p = bindMobileFlowClinicalPort(s.port)
    s.port.read = async () => {
      throw new Error('replaced')
    }
    const f = await p.read()
    s.facts.profile.name = 'mutated'
    expect(f.profile.name).toBe('QA')
    expect(Object.isFrozen(f.policy.hide)).toBe(true)
  })
  it('refuses missing or unknown mandatory public policy', async () => {
    const s = setup()
    delete (s.facts as unknown as { policy?: unknown }).policy
    await expect(s.bound.read()).rejects.toThrow()
    const t = setup()
    ;(t.facts.policy as { version: number }).version = 2
    await expect(t.bound.read()).rejects.toThrow()
  })
  it('whitelists tool facts without reviving unavailable targets or a block', async () => {
    const s = setup()
    const facts = flowClinicalFacts(s.facts)
    expect(facts).toMatchObject({
      clinical_policy: { pause_weight_loss_guidance: true },
      meta_kcal: null,
      meta_proteina_g: null,
      consumido_kcal: 0,
      progresso: { xp: 125 },
    })
    expect(JSON.stringify(facts)).not.toContain('deficit_block')
    expect(flowClinicalProposalAllowed(s.facts, 'training')).toBe(false)
    expect(flowClinicalProposalAllowed(s.facts, 'nutrition')).toBe(false)
  })
  it.each([
    consultaProgresso,
    consultaMetricas,
  ])('dispatches %s before any legacy database or formula read', async (tool) => {
    const s = setup()
    const result = await tool.execute({}, s.ctx)
    expect(result).toMatchObject({ meta_kcal: null, meta_proteina_g: null, progresso: { xp: 125 } })
    expect(s.from).not.toHaveBeenCalled()
    expect(s.revalidate).toHaveBeenCalled()
  })
  it('reads the actual bounded period through the clinical port', async () => {
    const s = setup()
    const result = await consultaResumoPeriodo.execute({ periodo: 'semana' }, s.ctx)
    expect(result).toMatchObject({ days: 2, avgNetBalance: null })
    expect(s.period).toHaveBeenCalledWith('semana')
    expect(s.from).not.toHaveBeenCalled()
  })
  it.each([
    propoePlanoDieta,
    propoePlanoTreino,
  ])('checks clinical restrictions before draft replay or provider', async (tool) => {
    const s = setup(true)
    const result = await tool.execute({}, s.ctx)
    expect(result).toMatchObject({
      success: false,
      retry_tool: false,
      error: 'clinical_guidance_unavailable',
    })
    expect(s.from).not.toHaveBeenCalled()
    expect(s.lookup).not.toHaveBeenCalled()
    expect(s.create).not.toHaveBeenCalled()
  })
  it('does not let another assistant identity use the mobile-only port', async () => {
    const s = setup()
    s.ctx.assistantIdentity = 'legacy'
    await expect(consultaMetricas.execute({}, s.ctx)).rejects.toThrow('Legacy read forbidden')
    expect(s.source).not.toHaveBeenCalled()
  })
})

it('preserves allergy/preferences context without obsolete numeric or phase authority', () => {
  expect(
    flowClinicalPreferences(
      'Alergia a amendoim. Prefere arroz. Meta antiga: 1800 kcal. Prefere reduzir calorias em recomposição.',
    ),
  ).toBe('Alergia a amendoim. Prefere arroz.')
})
