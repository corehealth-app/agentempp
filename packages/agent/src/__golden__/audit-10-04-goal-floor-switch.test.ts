/**
 * Golden — the revert switches of the goal floors (R4) also revert what the
 * MODEL reads. Audit of the client's WhatsApp group, 2026-10-04; rule in
 * docs/CALCULO-MPP.md §8b.
 *
 * Review of 2026-10-04, MEDIUM: with `BF_METHOD_FLOOR = 0` and
 * `IMC_GOAL_FLOOR = 0` the tools saved every goal again, but the descriptions
 * of define_protocolo and define_meta_peso had "10%" and "18,5" typed by hand
 * and kept telling the model "NÃO grava … NÃO diga que registrou". Reproduced
 * by the reviewer over 840 WhatsApp turns of a copy with every switch off: the
 * tool outputs matched commit 55294c4 and the prompt differed in all of them.
 *
 * The descriptions are now built from the two constants. Here each constant is
 * replaced by 0 in what tools.ts imports, and the text the model receives is
 * compared, byte for byte, with the text of commit 55294c4 (before R4).
 *
 * R4 itself: dito pelo cliente em 28/12/2025 (gordura) e 09/06/2026 (peso);
 * implementado em 2026-10-04 a pedido do Eduardo; confirmação do cliente
 * pendente.
 *
 * Declared pendencies (CLAUDE.md criterion 2; same line in docs/CALCULO-MPP.md §8c):
 *
 * > RC R4 — cenário os dois classificadores executados com o piso em 0 dentro da suíte (o piso é uma constante do módulo; aqui só o que tools.ts importa é trocado) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Conferido à mão em 2026-10-04, numa cópia com as duas constantes em 0, contra o commit 55294c4.
 */
import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { z } from 'zod'

type Row = Record<string, unknown>
type Floors = { bf: number | 'real'; imc: number | 'real' }

const USER_ID = '0b9f6f0e-0000-4000-8000-0000000000c4'
const NOW = new Date('2026-10-04T18:00:00.000Z')

/** tools.ts as the runtime would load it with the given floor constants. */
async function loadTools(floors: Floors) {
  vi.resetModules()
  if (floors.bf !== 'real') {
    const bf = floors.bf
    vi.doMock('../bf-goal-classifier.js', async (importOriginal) => ({
      ...(await importOriginal<typeof import('../bf-goal-classifier.js')>()),
      BF_METHOD_FLOOR: bf,
    }))
  }
  if (floors.imc !== 'real') {
    const imc = floors.imc
    vi.doMock('../weight-goal-classifier.js', async (importOriginal) => ({
      ...(await importOriginal<typeof import('../weight-goal-classifier.js')>()),
      IMC_GOAL_FLOOR: imc,
    }))
  }
  const tools = await import('../tools.js')
  return {
    tools,
    protocolo: tools.defineProtocolo.description,
    metaPeso: tools.defineMetaPeso.description,
    bfParam: describeOf(tools.defineMetaPeso.parameters, 'target_bf_percent'),
  }
}

/** The `.describe()` text of one parameter. It sits on the optional wrapper,
 * which tool-schema.ts does not send to the model today (audit 2026-09-29);
 * it is kept true all the same, for the day it is sent and for who reads the
 * code. */
function describeOf(parameters: z.ZodTypeAny, key: string): string {
  const object = parameters instanceof z.ZodEffects ? parameters.innerType() : parameters
  if (!(object instanceof z.ZodObject)) throw new Error('parameters are not an object schema')
  const field = (object.shape as Record<string, z.ZodTypeAny>)[key]
  return field?.description ?? ''
}

afterEach(() => {
  vi.doUnmock('../bf-goal-classifier.js')
  vi.doUnmock('../weight-goal-classifier.js')
  vi.resetModules()
})

// ── The text of commit 55294c4 (before R4), copied from tools.ts ────────────

const HEAD_PROTOCOLO =
  'Grava o protocolo nutricional + meta DO PACIENTE. ' +
  '⚠️ USE APENAS depois que: (1) cadastra_dados_iniciais foi chamada com peso/altura/BF; ' +
  '(2) você apresentou as 3 opções (recomposicao/ganho_massa/manutencao) e o paciente escolheu UMA explicitamente; ' +
  '(3) você apresentou o nível de fome (muita/moderada/pouca → 400/500/600 kcal de déficit; MAIS fome = MENOR déficit, pra proteger a adesão — regra do método) e ele escolheu — APENAS pra protocolo recomposicao. ' +
  'NÃO USE quando o paciente apenas DESEJOU genericamente ("quero emagrecer", "quero ganhar massa") — peça pra ele confirmar a opção. ' +
  'Parâmetros: ' +
  'protocol = "recomposicao" (déficit + preserva massa), "ganho_massa" (superávit), "manutencao" (sem ajuste). ' +
  'deficit_level = kcal/dia de déficit, APENAS pra recomposicao. 400=MUITA fome, 500=moderada, 600=POUCA fome (mais fome → MENOR déficit, pra não quebrar a adesão — regra fixa do método). Omita pra ganho_massa/manutencao. ' +
  'goal_type = "BF" (% gordura alvo) ou "IMC" (IMC alvo). ' +
  'goal_value = número absoluto da meta (ex: BF=15 ou IMC=23). Omita se não chegou nesse nível de detalhe.'

const HEAD_META_PESO =
  'Salva a META do paciente — PESO em kg OU PERCENTUAL DE GORDURA (BF%) — e retorna classificação automática da viabilidade. ' +
  'PASSE EXATAMENTE UM dos dois parâmetros (XOR):\n' +
  '  - `target_weight_kg`: quando o paciente fala em peso ("quero pesar 65kg", "minha meta é 70"). Faixa 30-300.\n' +
  '  - `target_bf_percent`: quando o paciente fala em gordura corporal ("quero chegar em 18%", "minha meta é 20% de BF"). Faixa 3-50.\n' +
  '⚠️ USE APENAS depois que: (1) cadastra_dados_iniciais foi chamada (peso, altura, sexo, e — se for BF — body_fat_percent atual); (2) o paciente declarou EXPLICITAMENTE o alvo. NÃO USE quando ele especulou ou pediu sua opinião antes.\n' +
  'Retorno: classificação (ideal/agressiva/sobrepeso/abaixo/manutenção) + números da meta (IMC alvo OU pp de gordura) + faixa saudável + semanas estimadas + MENSAGEM-BASE.\n' +
  'IMPORTANTE: a mensagem retornada NÃO é literal — varie o jeito de dizer mas MANTENHA os números. NUNCA invente IMC, faixa saudável nem BF essencial — use os da tool.'

const HEAD_BF_PARAM =
  'Percentual de gordura corporal alvo (1-60). Use quando paciente fala em %BF/composição corporal. Valores 1-4% caem em unhealthy_low; classifier lida com extremos.'

// ── The sentences R4 adds, as the model reads them with the floors on ───────

const PROTOCOLO_FLOOR_TAIL =
  ': NÃO diga que a meta foi registrada; explique o piso e ofereça uma meta a partir dele.'
const REFUSAL_TAIL =
  ' NÃO é gravada. O retorno traz refused=true, goal_saved=false e a meta anterior continua como estava. ' +
  'NÃO diga que registrou, NÃO chame a tool de novo com o mesmo valor: explique com a mensagem retornada e ofereça uma meta a partir do piso.\n'

describe('audit 2026-10-04 — R4: o interruptor do piso também reverte o que o modelo lê', () => {
  it('pisos ligados (10 e 18,5): as descrições dizem que a meta abaixo do piso não é gravada', async () => {
    const d = await loadTools({ bf: 'real', imc: 'real' })

    expect(d.protocolo).toBe(
      `${HEAD_PROTOCOLO} PISO DA META: BF abaixo de 10% ou IMC abaixo de 18,5 NÃO é gravado como meta. ` +
        `O protocolo e o déficit são gravados normalmente e o retorno traz goal_saved=false com goal_message${PROTOCOLO_FLOOR_TAIL}`,
    )
    expect(d.metaPeso).toBe(
      HEAD_META_PESO.replace(
        'Faixa 3-50.',
        'Abaixo de 10% a tool NÃO grava (piso do método).',
      ).replace(
        'IMPORTANTE: a mensagem retornada',
        `RECUSA (piso de segurança): meta de gordura corporal abaixo de 10%, ou meta de PESO que deixaria o IMC abaixo de 18,5 perdendo peso,${REFUSAL_TAIL}IMPORTANTE: a mensagem retornada`,
      ),
    )
    expect(d.bfParam).toBe(
      'Percentual de gordura corporal alvo (1-60). Use quando paciente fala em %BF/composição corporal. Abaixo de 10% a tool NÃO grava e devolve refused=true.',
    )
  })

  it('os dois pisos em 0: as três descrições voltam ao texto de antes, byte a byte, sem "NÃO grava"', async () => {
    const d = await loadTools({ bf: 0, imc: 0 })

    expect(d.protocolo).toBe(HEAD_PROTOCOLO)
    expect(d.metaPeso).toBe(HEAD_META_PESO)
    expect(d.bfParam).toBe(HEAD_BF_PARAM)
    for (const text of [d.protocolo, d.metaPeso, d.bfParam]) {
      expect(text).not.toMatch(/NÃO grava|NÃO é gravad|PISO DA META|RECUSA|refused|goal_saved/)
      expect(text).not.toMatch(/18,5|10%/)
    }
  })

  it('só o piso de gordura em 0: somem as frases de gordura, ficam as de peso e IMC', async () => {
    const d = await loadTools({ bf: 0, imc: 'real' })

    expect(d.protocolo).toBe(
      `${HEAD_PROTOCOLO} PISO DA META: IMC abaixo de 18,5 NÃO é gravado como meta. ` +
        `O protocolo e o déficit são gravados normalmente e o retorno traz goal_saved=false com goal_message${PROTOCOLO_FLOOR_TAIL}`,
    )
    expect(d.metaPeso).toBe(
      HEAD_META_PESO.replace(
        'IMPORTANTE: a mensagem retornada',
        `RECUSA (piso de segurança): meta de PESO que deixaria o IMC abaixo de 18,5 perdendo peso${REFUSAL_TAIL}IMPORTANTE: a mensagem retornada`,
      ),
    )
    expect(d.bfParam).toBe(HEAD_BF_PARAM)
    expect(d.protocolo + d.metaPeso + d.bfParam).not.toContain('10%')
  })

  it('só o piso de peso/IMC em 0: somem as frases de peso e IMC, ficam as de gordura', async () => {
    const d = await loadTools({ bf: 'real', imc: 0 })

    expect(d.protocolo).toBe(
      `${HEAD_PROTOCOLO} PISO DA META: BF abaixo de 10% NÃO é gravado como meta. ` +
        `O protocolo e o déficit são gravados normalmente e o retorno traz goal_saved=false com goal_message${PROTOCOLO_FLOOR_TAIL}`,
    )
    expect(d.metaPeso).toBe(
      HEAD_META_PESO.replace(
        'Faixa 3-50.',
        'Abaixo de 10% a tool NÃO grava (piso do método).',
      ).replace(
        'IMPORTANTE: a mensagem retornada',
        `RECUSA (piso de segurança): meta de gordura corporal abaixo de 10%${REFUSAL_TAIL}IMPORTANTE: a mensagem retornada`,
      ),
    )
    expect(d.protocolo + d.metaPeso + d.bfParam).not.toContain('18,5')
  })

  it('um piso com outro valor aparece no texto (a frase vem da constante, não de um número digitado)', async () => {
    const d = await loadTools({ bf: 12, imc: 19 })
    expect(d.protocolo).toContain(
      'PISO DA META: BF abaixo de 12% ou IMC abaixo de 19 NÃO é gravado como meta.',
    )
    expect(d.metaPeso).toContain('Abaixo de 12% a tool NÃO grava (piso do método).')
    expect(d.metaPeso).toContain(
      'meta de gordura corporal abaixo de 12%, ou meta de PESO que deixaria o IMC abaixo de 19 perdendo peso, NÃO é gravada.',
    )
    expect(d.bfParam).toContain('Abaixo de 12% a tool NÃO grava e devolve refused=true.')
  })
})

// ── define_protocolo with the floors at 0: the goal is saved again ──────────

function profileDb(profile: Row) {
  const updates: Row[] = []
  let current: Row = { user_id: USER_ID, ...profile }
  const db = {
    from(table: string) {
      if (table === 'global_config') {
        // No `calc.*` rows: the code defaults.
        return { select: () => ({ like: async () => ({ data: [], error: null }) }) }
      }
      if (table !== 'user_profiles') throw new Error(`unexpected table ${table}`)
      return {
        select: (columns: string) => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: Object.fromEntries(
                columns.split(',').map((c) => [c.trim(), current[c.trim()] ?? null]),
              ),
              error: null,
            }),
          }),
        }),
        update: (patch: Row) => ({
          eq: async () => {
            updates.push(patch)
            current = { ...current, ...patch }
            return { error: null }
          },
        }),
      }
    },
  }
  return { client: db as unknown as ServiceClient, updates, profile: () => current }
}

const MAN: Row = {
  sex: 'masculino',
  birth_date: '1990-01-01',
  height_cm: 180,
  weight_kg: 80,
  body_fat_percent: 12,
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: null,
  deficit_level: null,
  goal_type: null,
  goal_value: null,
}

describe('audit 2026-10-04 — R4: define_protocolo com os pisos em 0 grava a meta como antes', () => {
  // The negative goals are the second review's (2026-10-04, LOW): with both
  // floors at 0 the tool still dropped them ("goalValue < 0") and answered
  // goal_saved:false with "fica abaixo de 0%", while commit 55294c4 saved
  // goal_type 'BF' / goal_value -5. Reproduced by the reviewer over 1.435
  // calls of a copy with the constants at 0 (70 differed, all negative).
  it.each([
    ['BF', 7],
    ['IMC', 18],
    ['BF', -5],
    ['IMC', -1],
    ['BF', 0],
    ['IMC', 0],
  ] as const)('meta %s %s: gravada, e o retorno tem só as chaves de antes', async (goalType, goalValue) => {
    const { tools } = await loadTools({ bf: 0, imc: 0 })
    const db = profileDb(MAN)
    const args = tools.defineProtocolo.parameters.parse({
      protocol: 'recomposicao',
      deficit_level: 500,
      goal_type: goalType,
      goal_value: goalValue,
    })
    const result = await tools.defineProtocolo.execute(args, {
      supabase: db.client,
      userId: USER_ID,
      userWpp: '5511999990004',
      userTimezone: 'America/Sao_Paulo',
      referenceTimestamp: NOW,
    })

    expect(db.updates).toEqual([
      {
        current_protocol: 'recomposicao',
        deficit_level: 500,
        goal_type: goalType,
        goal_value: goalValue,
        updated_at: NOW.toISOString(),
      },
    ])
    expect(Object.keys(result).sort()).toEqual(
      [
        'calories_target_today',
        'formula_used',
        'protein_target_today_g',
        'protocol',
        'success',
      ].sort(),
    )
  })

  it('com os pisos ligados a mesma chamada (BF 7) descarta a meta — o teste acima mede o interruptor, não um acaso', async () => {
    const { tools } = await loadTools({ bf: 'real', imc: 'real' })
    const db = profileDb(MAN)
    const result = await tools.defineProtocolo.execute(
      tools.defineProtocolo.parameters.parse({
        protocol: 'recomposicao',
        deficit_level: 500,
        goal_type: 'BF',
        goal_value: 7,
      }),
      {
        supabase: db.client,
        userId: USER_ID,
        userWpp: '5511999990004',
        userTimezone: 'America/Sao_Paulo',
        referenceTimestamp: NOW,
      },
    )
    expect(db.updates[0]).toMatchObject({ goal_type: null, goal_value: null })
    expect(result).toMatchObject({ success: true, goal_saved: false })
  })

  it.each([
    ['BF', -5, { bf: 0, imc: 'real' }, true],
    ['IMC', -1, { bf: 'real', imc: 0 }, true],
    // The other floor is still on: its own goals keep being dropped.
    ['IMC', -1, { bf: 0, imc: 'real' }, false],
    ['BF', -5, { bf: 'real', imc: 0 }, false],
    ['BF', -5, { bf: 'real', imc: 'real' }, false],
    ['IMC', -1, { bf: 'real', imc: 'real' }, false],
  ] as const)('meta negativa %s %s com os pisos %o: gravada = %s (cada piso decide só a sua meta)', async (goalType, goalValue, floors, saved) => {
    const { tools } = await loadTools(floors)
    const db = profileDb(MAN)
    const result = await tools.defineProtocolo.execute(
      tools.defineProtocolo.parameters.parse({
        protocol: 'recomposicao',
        deficit_level: 500,
        goal_type: goalType,
        goal_value: goalValue,
      }),
      {
        supabase: db.client,
        userId: USER_ID,
        userWpp: '5511999990004',
        userTimezone: 'America/Sao_Paulo',
        referenceTimestamp: NOW,
      },
    )

    expect(db.updates[0]).toMatchObject(
      saved
        ? { current_protocol: 'recomposicao', goal_type: goalType, goal_value: goalValue }
        : { current_protocol: 'recomposicao', goal_type: null, goal_value: null },
    )
    if (saved) {
      expect(result).not.toHaveProperty('goal_saved')
      expect(result).not.toHaveProperty('goal_message')
    } else {
      expect(result).toMatchObject({ success: true, goal_saved: false })
    }
  })
})
