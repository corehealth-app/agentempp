/** Real proposal tool/generator/current BFF port/SQL; synthetic LLM and auxiliary
 * quota/history/events/numeric reader inputs. Parent owns a single ROLLBACK. */
import assert from 'node:assert/strict'
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import type { OpenRouterLLM } from '@mpp/providers'
import type { MobileAuthContext } from '../../../apps/admin/src/lib/mobile-api/auth'
import { createCurrentClinicalReadModel } from '../../../apps/admin/src/lib/mobile-api/current-clinical-read-model'
import { createCurrentFlowClinicalPort } from '../../../apps/admin/src/lib/mobile-api/current-flow-clinical-port'
import {
  createSupabaseCurrentFlowDraftAuthority,
  readCurrentFlowDraftContext,
} from '../../../apps/admin/src/lib/mobile-api/current-flow-draft-authority'
import { createCurrentFlowShortcutGuard } from '../../../apps/admin/src/lib/mobile-api/current-flow-draft-shortcut'
import { createSupabaseCurrentClinicalStateSource } from '../../../apps/admin/src/lib/mobile-api/supabase-current-clinical-state'
import { z } from '../../../packages/agent/node_modules/zod/index.js'
import { createPlanProposalTools } from '../../../packages/agent/src/tools/plan-proposal-tools'
import type { ToolContext } from '../../../packages/agent/src/tools/types'
import { buildDailyState } from '../../../packages/core/src/daily-state'

if (process.env.PERFORME_FLOW_DRAFT_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw new Error('Owned parent required')
const iterator = createInterface({ input: process.stdin, crlfDelay: Infinity })[
  Symbol.asyncIterator
]()
let tail: Promise<unknown> = Promise.resolve()
function request(value: object): Promise<unknown> {
  const next = tail.then(async () => {
    process.stdout.write(JSON.stringify(value) + '\n')
    const result = await iterator.next()
    if (result.done) throw new Error('Parent closed')
    return JSON.parse(result.value)
  })
  tail = next.then(
    () => {},
    () => {},
  )
  return next
}
async function run() {
  const seed = (await request({ type: 'seed' })) as {
      owner: string
      turns: Record<string, string>
    },
    owner = seed.owner
  const rpcNames: string[] = [],
    auxiliary: string[] = []
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => {
      assert.equal(args.p_user_id, owner)
      assert.notEqual(name, 'create_plan_draft_atomic')
      rpcNames.push(name)
      return request({ type: 'rpc', name, args })
    },
    from(table: string) {
      let single = false,
        insert = false
      const filters: Record<string, unknown> = {}
      const promise = Promise.resolve().then(async () => {
        auxiliary.push(table)
        if (table === 'messages') {
          assert.equal(single, true)
          assert.equal(filters.user_id, owner)
          assert.equal(filters.provider, 'mobile_flow')
          assert.equal(filters.direction, 'in')
          assert.equal(filters.role, 'user')
          return request({ type: 'turn', providerID: filters.provider_message_id })
        }
        assert.ok(
          ['product_events', 'plan_drafts', 'meal_logs'].includes(table),
          'unexpected auxiliary source',
        )
        assert.ok(!insert || table === 'product_events', 'no auxiliary draft/plan write')
        return { data: insert ? null : [], error: null }
      })
      const builder = Object.assign(promise, {
        select: () => builder,
        eq: (k: string, v: unknown) => {
          filters[k] = v
          return builder
        },
        gte: () => builder,
        in: () => builder,
        order: () => builder,
        limit: () => builder,
        maybeSingle: () => {
          single = true
          return builder
        },
        insert: () => {
          insert = true
          return builder
        },
      })
      return builder
    },
  } as unknown as ServiceClient
  const authority = createSupabaseCurrentFlowDraftAuthority(client, owner),
    state = createSupabaseCurrentClinicalStateSource(client)
  const auth: MobileAuthContext = {
    userId: owner,
    authUserId: owner,
    accessToken: 'synthetic-only',
    identity: { id: owner, email: null, emailConfirmedAt: null },
    patient: {
      id: owner,
      authUserId: owner,
      email: null,
      name: 'Synthetic draft QA',
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
  function port() {
    return createCurrentFlowClinicalPort(
      {
        auth,
        supabase: client,
        requestId: 'draft-bridge',
        request: new Request(
          'https://owned.test/api/mobile/v1/flow/chat?clinical_policy=current_clinical_v1',
        ),
      },
      {
        state,
        drafts: authority,
        applyDaily: async () => {},
        closeDays: async () => {},
        periodRows: async () => [],
        createReadModel: () =>
          createCurrentClinicalReadModel(client, state, {
            today: async () => {
              const current = readCurrentFlowDraftContext(await authority.capture(), owner),
                d = current.day
              assert.ok(d)
              const phase = d.current_protocol
              assert.ok(phase)
              assert.ok(d.calories_target !== null && d.protein_target !== null)
              return buildDailyState({
                localDate: current.state.date,
                generatedAt: current.state.observed_at,
                protocol: phase,
                calculatedTargets: {
                  calories_target: d.calories_target,
                  protein_target: d.protein_target,
                },
                snapshot: {
                  caloriesConsumed: 0,
                  caloriesTarget: d.calories_target,
                  proteinG: 0,
                  proteinTarget: d.protein_target,
                  carbsG: 0,
                  fatG: 0,
                  exerciseCalories: 0,
                  waterConsumedMl: 0,
                  protocol: phase,
                  dayClosed: false,
                  dayStatus: null,
                  updatedAt: null,
                },
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
            },
            progress: async () => null,
            plan: async () => ({ training: null, nutrition: [] }),
            trends: async () => {
              throw new Error('unused')
            },
            profile: async () => {
              throw new Error('unused')
            },
          }),
      },
    )
  }
  let generations = 0
  const llm = {
    complete: async () => {
      generations++
      return {
        content: JSON.stringify({
          daily_meals: [0, 1].map((i) => ({
            meal_type: i ? 'almoco' : 'cafe',
            time_suggestion: i ? '12:30' : '07:30',
            items: [
              {
                food_name: 'ovo',
                quantity_g: 100,
                kcal: 1000,
                protein_g: 72,
                carbs_g: 1,
                fat_g: 8,
              },
            ],
            total_kcal: 1000,
            total_protein_g: 72,
          })),
          shopping_list: [{ category: 'proteínas', food_name: 'ovo', quantity_g: 500 }],
        }),
        model: 'synthetic-local',
        stop_reason: 'end_turn',
      }
    },
  } as unknown as OpenRouterLLM
  const [training, diet] = createPlanProposalTools({
    training: z.object({}),
    diet: z.object({
      horizon: z.enum(['daily', 'weekly']).optional(),
      meals_per_day: z.number().optional(),
    }),
  })
  const ctx = (turn: string, model: OpenRouterLLM = llm): ToolContext =>
    ({
      userId: owner,
      providerMessageId: turn,
      assistantIdentity: 'flow',
      flowClinical: port(),
      llm: model,
      supabase: client,
    }) as ToolContext
  const a = ctx(seed.turns.A),
    first = (await diet.execute({ horizon: 'daily', meals_per_day: 2 }, a)) as {
      success: boolean
      draft_id: string
    }
  assert.equal(first.success, true)
  assert.ok(first.draft_id)
  assert.equal(generations, 1)
  let witness = (await request({ type: 'witness' })) as Record<string, unknown>
  assert.equal(witness.drafts, 1)
  assert.equal(witness.origins, 1)
  assert.equal(witness.active_plans, 0)
  const replay = (await diet.execute({ horizon: 'daily' }, ctx(seed.turns.A))) as {
    draft_id: string
    replayed: boolean
  }
  assert.equal(replay.draft_id, first.draft_id)
  assert.equal(replay.replayed, true)
  assert.equal(generations, 1)
  await request({ type: 'edit', id: first.draft_id })
  const editedContext = ctx(seed.turns.A),
    edited = (await diet.execute({}, editedContext)) as { draft_id: string; replayed: boolean }
  assert.equal(edited.draft_id, first.draft_id)
  assert.equal(edited.replayed, true)
  assert.equal(generations, 1)
  const stored = await editedContext.flowClinical!.drafts!.lookup({
    domain: 'nutrition',
    requestKey: seed.turns.A + ':propoe_plano_dieta',
  })
  assert.equal(stored?.payload?.notes, 'QA edited notes')
  const guard = createCurrentFlowShortcutGuard(owner, authority),
    current = readCurrentFlowDraftContext(await authority.capture(), owner)
  assert.deepEqual(
    await guard('qa-current-draft-A', { id: first.draft_id, domain: 'nutrition' }, current.state),
    { id: first.draft_id, domain: 'nutrition' },
  )
  assert.equal(
    await guard('qa-current-draft-B', { id: first.draft_id, domain: 'nutrition' }, current.state),
    null,
  )
  let trainingGenerations = 0
  const trainingLLM = {
    complete: async () => {
      trainingGenerations++
      return {
        content: JSON.stringify({
          plan_type: 'split',
          weekly_schedule: [
            {
              day: 'seg',
              focus: 'Inferiores',
              duration_min: 60,
              exercises: [
                {
                  name: 'Agachamento',
                  muscle_group: 'glúteos',
                  sets: 4,
                  reps_range: '8-12',
                  rest_seconds: 90,
                },
              ],
            },
          ],
          progression_rule: 'Adicione 1 rep por treino.',
        }),
        model: 'synthetic-local',
        finishReason: 'stop',
      }
    },
  } as unknown as OpenRouterLLM
  const trainingArgs = {
    available_equipment: ['halteres'],
    location: 'casa',
    days_per_week: 1,
    training_level: 'iniciante',
  }
  const proposed = (await training.execute(trainingArgs, ctx(seed.turns.T, trainingLLM))) as {
    success: boolean
    draft_id: string
  }
  assert.equal(proposed.success, true)
  assert.ok(proposed.draft_id)
  const trainingReplay = (await training.execute(trainingArgs, ctx(seed.turns.T, trainingLLM))) as {
    draft_id: string
    replayed: boolean
  }
  assert.equal(trainingReplay.draft_id, proposed.draft_id)
  assert.equal(trainingReplay.replayed, true)
  assert.equal(trainingGenerations, 1)
  await request({ type: 'arm' })
  await assert.rejects(diet.execute({ horizon: 'daily', meals_per_day: 2 }, ctx(seed.turns.B)), {
    code: 'mobile_current_clinical_changed',
  })
  assert.equal(generations, 2)
  witness = (await request({ type: 'witness' })) as Record<string, unknown>
  assert.equal(witness.drafts, 2)
  assert.equal(witness.origins, 2)
  assert.equal(witness.active_plans, 0)
  assert.equal(witness.revision, '2')
  assert.ok(!rpcNames.includes('create_plan_draft_atomic'))
  process.stdout.write(
    JSON.stringify({
      type: 'result',
      status: 'PASS_ACTUAL_FLOW_TOOL_GENERATOR_BFF_SQL',
      cases: [
        'diet-created',
        'same-turn-replay',
        'edited-replay',
        'shortcut-same-turn',
        'shortcut-foreign-turn',
        'training-created',
        'training-replay',
        'stale-CAS-refused',
      ],
      generations,
      trainingGenerations,
      RPCs: rpcNames.length,
      legacy_write_RPCs: 0,
      auxiliary_synthetic_tables: [...new Set(auxiliary)],
    }) + '\n',
  )
}
run().then(
  () => process.exit(0),
  (error) => {
    process.stderr.write(String(error.stack ?? error) + '\n')
    process.stdout.write(JSON.stringify({ type: 'failure' }) + '\n')
    process.exit(1)
  },
)
