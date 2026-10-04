import { DEFAULT_CALC_CONFIG } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { loadDailyTargets, loadDailyTargetsWithProtocol } from './calc-targets.js'

function makeClient(result: { data: Record<string, unknown> | null; error: unknown }) {
  const terminal = {
    maybeSingle: async () => result,
  }
  return {
    from: () => ({
      select: () => ({
        eq: () => terminal,
      }),
    }),
  }
}

describe('loadDailyTargets', () => {
  it('propaga erro de perfil em vez de calcular metas com perfil vazio', async () => {
    const client = makeClient({ data: null, error: { message: 'profile lookup failed' } })

    await expect(loadDailyTargets(client, 'user-1', DEFAULT_CALC_CONFIG)).rejects.toThrow(
      'profile lookup failed',
    )
  })

  it('mantém fallback funcional quando a consulta é válida e o perfil ainda não existe', async () => {
    const client = makeClient({ data: null, error: null })

    await expect(loadDailyTargets(client, 'user-1', DEFAULT_CALC_CONFIG)).resolves.toEqual(
      expect.objectContaining({ calories_target: null, protein_target: null }),
    )
  })
})

// `cadastra_dados_iniciais` decides what to hand to the model from the
// protocol of the very row the targets were computed with (rule M1,
// docs/CALCULO-MPP.md §1b).
describe('loadDailyTargetsWithProtocol', () => {
  const row = {
    sex: 'masculino',
    birth_date: '1982-01-01',
    height_cm: 187,
    weight_kg: 100,
    body_fat_percent: null,
    activity_level: 'moderado',
    training_frequency: 5,
    water_intake: 'moderado',
    hunger_level: 'pouca',
    current_protocol: 'recomposicao',
    goal_type: null,
    goal_value: null,
    deficit_level: 600,
  }

  it.each([
    'recomposicao',
    'ganho_massa',
    'manutencao',
    null,
  ])('devolve o protocolo da linha lida (%s) e as mesmas metas de loadDailyTargets', async (current_protocol) => {
    const client = makeClient({ data: { ...row, current_protocol }, error: null })

    const loaded = await loadDailyTargetsWithProtocol(client, 'user-1', DEFAULT_CALC_CONFIG)

    expect(loaded.currentProtocol).toBe(current_protocol)
    expect(loaded.targets).toEqual(await loadDailyTargets(client, 'user-1', DEFAULT_CALC_CONFIG))
  })

  it('perfil inexistente: protocolo null e metas null', async () => {
    const client = makeClient({ data: null, error: null })

    await expect(
      loadDailyTargetsWithProtocol(client, 'user-1', DEFAULT_CALC_CONFIG),
    ).resolves.toEqual({
      targets: { calories_target: null, protein_target: null },
      currentProtocol: null,
    })
  })

  it('propaga o erro de leitura do perfil', async () => {
    const client = makeClient({ data: null, error: { message: 'profile lookup failed' } })

    await expect(
      loadDailyTargetsWithProtocol(client, 'user-1', DEFAULT_CALC_CONFIG),
    ).rejects.toThrow('profile lookup failed')
  })
})
