import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { clearCalcConfigCache } from './calc-config-loader.js'
import { cadastraDadosIniciais, deleteUser } from './tools.js'

function makeProfileContext(
  options: {
    nameUpdateError?: string
    metricsRow?: Record<string, unknown>
    /** The `user_profiles` row; the upsert of the tool is merged into it. */
    profileRow?: Record<string, unknown>
    /** `global_config` rows `calc.*`. */
    configRows?: Array<{ key: string; value: unknown }>
    /** Extra fields of the tool context (e.g. the Flow identity). */
    contextExtras?: Record<string, unknown>
  } = {},
) {
  const profileUpserts: Array<Record<string, unknown>> = []
  let profileRow = options.profileRow ?? null
  const supabase = {
    from(table: string) {
      if (table === 'user_profiles') {
        return {
          upsert: async (values: Record<string, unknown>) => {
            profileUpserts.push(values)
            if (profileRow) profileRow = { ...profileRow, ...values }
            return { error: null }
          },
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({ data: profileRow, error: null }),
            }),
          }),
        }
      }
      if (table === 'users') {
        return {
          update: () => ({
            eq: async () => ({
              error: options.nameUpdateError ? { message: options.nameUpdateError } : null,
            }),
          }),
        }
      }
      if (table === 'v_user_metrics') {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({ data: options.metricsRow ?? null, error: null }),
            }),
          }),
        }
      }
      if (table === 'global_config') {
        return {
          select: () => ({
            like: async () => ({ data: options.configRows ?? [], error: null }),
          }),
        }
      }
      throw new Error(`unexpected table: ${table}`)
    },
  }
  return {
    supabase,
    profileUpserts,
    context: {
      supabase,
      userId: 'user-1',
      userWpp: '15555550100',
      referenceTimestamp: new Date('2026-07-11T12:00:00.000Z'),
      ...options.contextExtras,
    },
  }
}

// `loadCalcConfig` caches for 60 s: each test loads its own `global_config`.
beforeEach(() => clearCalcConfigCache())
afterEach(() => clearCalcConfigCache())

describe('profile write safety', () => {
  it('cadastra_dados_iniciais não confirma nome que falhou ao gravar', async () => {
    const { context } = makeProfileContext({ nameUpdateError: 'name write failed' })

    await expect(
      cadastraDadosIniciais.execute({ name: 'Nome Teste' }, context as never),
    ).rejects.toThrow('name write failed')
  })

  it('cadastra_dados_iniciais preserva frequência sedentária igual a zero', async () => {
    const { context, profileUpserts } = makeProfileContext()

    await expect(
      cadastraDadosIniciais.execute({ training_frequency: 0 }, context as never),
    ).resolves.toMatchObject({ success: true })
    expect(profileUpserts[0]).toMatchObject({ training_frequency: 0 })
  })

  it('cadastra_dados_iniciais devolve metrics null quando a view não tem linha', async () => {
    const { context } = makeProfileContext()

    const result = await cadastraDadosIniciais.execute({ hunger_level: 'pouca' }, context as never)

    expect(result.metrics).toBeNull()
  })

  it('delete_user não confirma exclusão quando status não foi persistido', async () => {
    const events: Array<Record<string, unknown>> = []
    const context = {
      userId: 'user-1',
      userWpp: '15555550100',
      supabase: {
        from(table: string) {
          if (table === 'users') {
            return {
              update: () => ({
                eq: async () => ({ error: { message: 'delete status write failed' } }),
              }),
            }
          }
          if (table === 'product_events') {
            return {
              insert: async (event: Record<string, unknown>) => {
                events.push(event)
                return { error: null }
              },
            }
          }
          throw new Error(`unexpected table: ${table}`)
        },
      },
    }

    await expect(deleteUser.execute({ confirmacao: 'confirmo' }, context as never)).rejects.toThrow(
      'delete status write failed',
    )
    expect(events).toHaveLength(0)
  })

  it('delete_user registra quando a janela segura para purge começou', async () => {
    const userUpdates: Array<Record<string, unknown>> = []
    const context = {
      userId: 'user-1',
      userWpp: '15555550100',
      supabase: {
        from(table: string) {
          if (table === 'users') {
            return {
              update: (values: Record<string, unknown>) => {
                userUpdates.push(values)
                return { eq: async () => ({ error: null }) }
              },
            }
          }
          if (table === 'product_events') {
            return { insert: async () => ({ error: null }) }
          }
          throw new Error(`unexpected table: ${table}`)
        },
      },
    }

    await expect(
      deleteUser.execute({ confirmacao: 'confirmo' }, context as never),
    ).resolves.toMatchObject({ success: true })
    const userUpdate = userUpdates[0]
    expect(userUpdate).toMatchObject({ status: 'deleted' })
    expect(new Date(String(userUpdate?.updated_at)).toISOString()).toBe(userUpdate?.updated_at)
  })
})

// ── Rule M1 (docs/CALCULO-MPP.md §1b): which `metrics` the model receives ────
//
// The view `v_user_metrics` maps hunger to a `protein_factor` (pouca 1.6 /
// moderada 1.8 / muita 2.0) in SQL. The tool stops handing it over ONLY when
// it contradicts the target it returns next to it: the profile is in
// recomposição after this call AND the fixed 1.5 g/kg is on (report C3-38).
// In every other case the return is the view's row, key by key, as on HEAD
// (review of 2026-10-04: the first version of M1 dropped the key in every
// protocol and channel, and the revert switch did not bring it back).
//
// Stated by the client on 2026-04-15 and 2026-05-15; implemented on
// 2026-10-04 at Eduardo's request; the client's confirmation is pending.
describe('cadastra_dados_iniciais — metrics.protein_factor da view segue a regra M1', () => {
  /** `calc.protein_factors` of staging, read on 2026-10-04. */
  const STAGING_CASCADE = {
    key: 'calc.protein_factors',
    value: {
      muita: 1.6,
      pouca: 1.8,
      moderada: 1.8,
      training_low: 1.7,
      optimal_mid_training: 1.9,
      optimal_high_training: 2,
    },
  }
  const switchRow = (value: unknown) => ({ key: 'calc.recomp_protein_g_per_kg', value })

  const profile = (
    current_protocol: 'recomposicao' | 'ganho_massa' | 'manutencao' | null,
    overrides: Record<string, unknown> = {},
  ) => ({
    user_id: 'user-1',
    sex: 'masculino',
    birth_date: '1982-01-01',
    height_cm: 187,
    weight_kg: 100,
    body_fat_percent: null,
    activity_level: 'moderado',
    training_frequency: 5,
    water_intake: 'moderado',
    hunger_level: 'pouca',
    current_protocol,
    goal_type: null,
    goal_value: null,
    deficit_level: current_protocol === 'recomposicao' ? 600 : null,
    ...overrides,
  })

  /** What the view returns for the profile above (hand-written from its SQL). */
  const viewRow = () => ({
    user_id: 'user-1',
    age: 44,
    bmr: 1953.75,
    activity_factor: 1.55,
    lbm: 100,
    imc: 28.6,
    protein_factor: 1.6,
  })
  const viewRowWithoutFactor = {
    user_id: 'user-1',
    age: 44,
    bmr: 1953.75,
    activity_factor: 1.55,
    lbm: 100,
    imc: 28.6,
  }

  /** What the pipeline adds to the tool context on the app's Flow channel. */
  const FLOW_CONTEXT_EXTRAS = { assistantIdentity: 'flow' }

  async function run(options: Parameters<typeof makeProfileContext>[0]) {
    const metricsRow = viewRow()
    const { context } = makeProfileContext({ metricsRow, ...options })
    const result = await cadastraDadosIniciais.execute({ hunger_level: 'pouca' }, context as never)
    expect(result.success).toBe(true)
    // The row read from the database is never mutated.
    expect(metricsRow).toEqual(viewRow())
    return result
  }

  // ── The one case the key is dropped ──────────────────────────────────────

  it.each([
    ['sem nenhuma linha calc.* (padrão do código)', []],
    ['com a cascata do staging no banco', [STAGING_CASCADE]],
    ['com a linha do fator em 1.5', [STAGING_CASCADE, switchRow(1.5)]],
    ['com a linha do fator em 1.2 (número dentro da faixa)', [STAGING_CASCADE, switchRow(1.2)]],
  ])('recomposição com o fator fixo LIGADO (%s): o retorno não contém protein_factor', async (_label, configRows) => {
    const result = await run({ profileRow: profile('recomposicao'), configRows })

    expect(result.metrics).toEqual(viewRowWithoutFactor)
    expect(JSON.stringify(result)).not.toContain('protein_factor')
    // Mifflin-St Jeor 1953.75 × 1.2 − 600 = 1744.5.
    expect(result.calories_target_today).toBe(1745)
  })

  it('recomposição com o fator fixo ligado: 150 g e nenhum 1.6 no retorno (C3-38)', async () => {
    const result = await run({ profileRow: profile('recomposicao'), configRows: [STAGING_CASCADE] })

    expect(result.protein_target_today_g).toBe(150)
    expect(Object.values(result.metrics as Record<string, unknown>)).not.toContain(1.6)
  })

  // A typing mistake in the row falls back to the code default (1.5), so the
  // rule is still on and the key is still dropped.
  it.each([
    ['texto "1.5"', '1.5'],
    ['99', 99],
    ['-1', -1],
  ])('recomposição com a linha inválida (%s): a regra continua ligada — 150 g, sem protein_factor', async (_label, value) => {
    const result = await run({
      profileRow: profile('recomposicao'),
      configRows: [STAGING_CASCADE, switchRow(value)],
    })

    expect(result.protein_target_today_g).toBe(150)
    expect(result.metrics).toEqual(viewRowWithoutFactor)
  })

  // ── The revert switch brings the key back ────────────────────────────────

  it.each([
    ['0 (o valor recomendado)', 0],
    ['null', null],
  ])('recomposição com o interruptor DESLIGADO (linha = %s): a linha da view volta inteira, como no HEAD', async (_label, value) => {
    const result = await run({
      profileRow: profile('recomposicao'),
      configRows: [STAGING_CASCADE, switchRow(value)],
    })

    expect(result.metrics).toEqual(viewRow())
    expect(result.metrics).toHaveProperty('protein_factor', 1.6)
    // The cascade is back for the target too: pouca + 5 treinos → 2.0 × 100 kg.
    expect(result.protein_target_today_g).toBe(200)
    expect(result.calories_target_today).toBe(1745)
  })

  // ── Every other protocol: untouched, switch on or off ────────────────────

  // Review (balance lens): "Paciente de ganho de massa no WhatsApp chama
  // cadastra_dados_iniciais({hunger_level:'pouca'}) com a view devolvendo
  // protein_factor 1.6: em HEAD o retorno era metrics com protein_factor 1.6".
  it.each([
    ['ganho_massa', 'ligado (sem linha)', [STAGING_CASCADE]],
    ['ganho_massa', 'desligado (linha = 0)', [STAGING_CASCADE, switchRow(0)]],
    ['ganho_massa', 'desligado (linha = null)', [STAGING_CASCADE, switchRow(null)]],
    ['ganho_massa', 'ligado, padrão do código', []],
    ['manutencao', 'ligado (sem linha)', [STAGING_CASCADE]],
    ['manutencao', 'desligado (linha = 0)', [STAGING_CASCADE, switchRow(0)]],
    ['manutencao', 'ligado, padrão do código', []],
    [null, 'ligado (sem linha)', [STAGING_CASCADE]],
    [null, 'desligado (linha = 0)', [STAGING_CASCADE, switchRow(0)]],
    [null, 'ligado, padrão do código', []],
  ] as const)('protocolo %s, interruptor %s: metrics é a linha da view com protein_factor 1.6', async (protocol, _label, configRows) => {
    const result = await run({ profileRow: profile(protocol), configRows: [...configRows] })

    expect(result.metrics).toEqual(viewRow())
    expect(Object.keys(result.metrics as Record<string, unknown>)).toEqual(Object.keys(viewRow()))
    expect(result.metrics).toHaveProperty('protein_factor', 1.6)
  })

  it('perfil ainda sem linha em user_profiles (protocolo desconhecido): a linha da view volta inteira', async () => {
    const result = await run({ configRows: [STAGING_CASCADE] })

    expect(result.metrics).toEqual(viewRow())
    expect(result.calories_target_today).toBeNull()
    expect(result.protein_target_today_g).toBeNull()
  })

  it('a view sem linha: metrics null em qualquer protocolo', async () => {
    for (const protocol of ['recomposicao', 'ganho_massa', 'manutencao', null] as const) {
      clearCalcConfigCache()
      const { context } = makeProfileContext({ profileRow: profile(protocol) })
      const result = await cadastraDadosIniciais.execute(
        { hunger_level: 'pouca' },
        context as never,
      )
      expect(result.metrics, String(protocol)).toBeNull()
    }
  })

  // ── Every channel ────────────────────────────────────────────────────────

  it.each([
    ['recomposicao', viewRowWithoutFactor],
    ['ganho_massa', viewRow()],
    [null, viewRow()],
  ] as const)('no Flow do app (assistantIdentity flow), protocolo %s: mesma regra do WhatsApp', async (protocol, expected) => {
    const result = await run({
      profileRow: profile(protocol),
      configRows: [STAGING_CASCADE],
      contextExtras: FLOW_CONTEXT_EXTRAS,
    })

    expect(result.metrics).toEqual(expected)
  })
})
