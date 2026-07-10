import { describe, expect, it } from 'vitest'
import {
  buildPersonalWindowsFromLogs,
  hourInTimezone,
  type MealRegistrationSample,
  type MealType,
  MIN_SAMPLES_FOR_PERSONAL,
  type PersonalMealWindows,
  percentile,
  resolveMealTypeByHour,
} from './personal-meal-windows.js'

function sample(meal_type: MealType, hour: number, day: number): MealRegistrationSample {
  return {
    meal_type,
    hour,
    local_date: `2026-06-${String(day).padStart(2, '0')}`,
    registration_key: `${meal_type}-${day}`,
  }
}

describe('hourInTimezone', () => {
  it('converte UTC 21:00 → 18h ET (UTC-3, sem DST aqui é EDT-4 → 17)', () => {
    // 2025-06-15T21:00:00Z em EDT (UTC-4) = 17h
    expect(hourInTimezone('2025-06-15T21:00:00Z', 'America/New_York')).toBe(17)
  })
  it('converte UTC 21:00 → 18h BRT (UTC-3)', () => {
    expect(hourInTimezone('2025-06-15T21:00:00Z', 'America/Sao_Paulo')).toBe(18)
  })
  it('lida com meia-noite local sem virar 24', () => {
    // 03:00 UTC = 00:00 ART (UTC-3)
    expect(hourInTimezone('2025-06-15T03:00:00Z', 'America/Sao_Paulo')).toBe(0)
  })
})

describe('percentile', () => {
  it('p50 de [1,2,3,4,5] = 3', () => {
    expect(percentile([1, 2, 3, 4, 5], 50)).toBeCloseTo(3, 5)
  })
  it('p10 de [10,11,12,13,14] = 10.4', () => {
    expect(percentile([10, 11, 12, 13, 14], 10)).toBeCloseTo(10.4, 5)
  })
  it('p90 de [10,11,12,13,14] = 13.6', () => {
    expect(percentile([10, 11, 12, 13, 14], 90)).toBeCloseTo(13.6, 5)
  })
  it('1 elemento → retorna ele mesmo', () => {
    expect(percentile([7], 90)).toBe(7)
  })
  it('lista vazia → 0', () => {
    expect(percentile([], 50)).toBe(0)
  })
})

describe('buildPersonalWindowsFromLogs — Roberto janta 17-19h ET', () => {
  it('com 5+ amostras de jantar 17-19h, gera janela pessoal 17-19', () => {
    const logs: MealRegistrationSample[] = [
      sample('jantar', 17, 1),
      sample('jantar', 18, 2),
      sample('jantar', 19, 3),
      sample('jantar', 18, 4),
      sample('jantar', 17, 5),
      sample('jantar', 19, 6),
    ]
    const windows = buildPersonalWindowsFromLogs(logs)
    const jantar = windows.get('jantar')
    expect(jantar).toBeDefined()
    expect(jantar?.p10).toBe(17)
    expect(jantar?.p90).toBe(19)
    expect(jantar?.sample_count).toBe(6)
  })

  it('com <5 amostras NÃO gera janela (fallback global esperado)', () => {
    const logs: MealRegistrationSample[] = [
      sample('jantar', 17, 1),
      sample('jantar', 18, 2),
      sample('jantar', 19, 3),
      sample('jantar', 18, 4),
    ]
    const windows = buildPersonalWindowsFromLogs(logs)
    expect(windows.get('jantar')).toBeUndefined()
  })

  it('grupos diferentes — só ativa quem tem ≥5', () => {
    const logs: MealRegistrationSample[] = [
      // 5x cafe
      sample('cafe', 7, 1),
      sample('cafe', 8, 2),
      sample('cafe', 9, 3),
      sample('cafe', 8, 4),
      sample('cafe', 7, 5),
      // 2x almoco (insuficiente)
      sample('almoco', 13, 1),
      sample('almoco', 14, 2),
    ]
    const windows = buildPersonalWindowsFromLogs(logs)
    expect(windows.has('cafe')).toBe(true)
    expect(windows.has('almoco')).toBe(false)
  })

  it('ceia com wrap noturno (23,0,1,2,23,0) — janela cruza meia-noite', () => {
    const logs: MealRegistrationSample[] = [
      sample('ceia', 23, 1),
      sample('ceia', 0, 2),
      sample('ceia', 1, 3),
      sample('ceia', 2, 4),
      sample('ceia', 23, 5),
      sample('ceia', 0, 6),
    ]
    const windows = buildPersonalWindowsFromLogs(logs)
    const ceia = windows.get('ceia')
    expect(ceia).toBeDefined()
    // p10/p90 devem caír na faixa 23-2 (wrap), não 0-23.
    // Sequência normalizada: [23,24,25,26,23,24] → ordenada [23,23,24,24,25,26]
    // p10≈23, p90≈25.5 → arredondado e mod 24 → p10=23, p90=2
    expect(ceia?.p10).toBe(23)
    expect(ceia?.p90).toBe(2)
  })
})

describe('resolveMealTypeByHour — fallback global', () => {
  const emptyPersonal: PersonalMealWindows = { windows: new Map(), totalLogs: 0 }

  it('sem janela pessoal, 12h → almoco (global)', () => {
    const r = resolveMealTypeByHour(12, emptyPersonal)
    expect(r.expected).toBe('almoco')
    expect(r.source).toBe('global')
  })
  it('sem janela pessoal, 7h → cafe (global)', () => {
    expect(resolveMealTypeByHour(7, emptyPersonal).expected).toBe('cafe')
  })
  it('sem janela pessoal, 16h → lanche (global)', () => {
    expect(resolveMealTypeByHour(16, emptyPersonal).expected).toBe('lanche')
  })
  it('sem janela pessoal, 20h → jantar (global)', () => {
    expect(resolveMealTypeByHour(20, emptyPersonal).expected).toBe('jantar')
  })
  it('sem janela pessoal, 2h → ceia', () => {
    expect(resolveMealTypeByHour(2, emptyPersonal).expected).toBe('ceia')
  })
})

describe('resolveMealTypeByHour — Roberto ET (janta 17-19h)', () => {
  it('com janela pessoal jantar=17-19, 17h NÃO vira lanche, vira jantar', () => {
    const personal: PersonalMealWindows = {
      windows: new Map([
        [
          'jantar' as MealType,
          {
            meal_type: 'jantar' as MealType,
            p10: 17,
            p90: 19,
            sample_count: 8,
            distinct_day_count: 8,
          },
        ],
      ]),
      totalLogs: 30,
    }
    const r = resolveMealTypeByHour(17, personal)
    expect(r.expected).toBe('jantar')
    expect(r.source).toBe('personal')
  })

  it('17h sem janela pessoal jantar → cai pra lanche (global)', () => {
    const personal: PersonalMealWindows = { windows: new Map(), totalLogs: 0 }
    const r = resolveMealTypeByHour(17, personal)
    expect(r.expected).toBe('lanche')
    expect(r.source).toBe('global')
  })

  it('hora fora da janela pessoal → cai pra global', () => {
    // Paciente tem janela cafe 7-9, mas hora atual é 13 → cai pra global=almoco
    const personal: PersonalMealWindows = {
      windows: new Map([
        [
          'cafe' as MealType,
          {
            meal_type: 'cafe' as MealType,
            p10: 7,
            p90: 9,
            sample_count: 10,
            distinct_day_count: 10,
          },
        ],
      ]),
      totalLogs: 30,
    }
    const r = resolveMealTypeByHour(13, personal)
    expect(r.expected).toBe('almoco')
    expect(r.source).toBe('global')
  })

  it('sobreposição: janelas almoco 13-15 + lanche 14-16, hora 14 → escolhe a mais estreita', () => {
    // span almoco = 2, span lanche = 2 → empate, alfabético → almoco
    const personal: PersonalMealWindows = {
      windows: new Map([
        [
          'almoco' as MealType,
          {
            meal_type: 'almoco' as MealType,
            p10: 13,
            p90: 15,
            sample_count: 6,
            distinct_day_count: 6,
          },
        ],
        [
          'lanche' as MealType,
          {
            meal_type: 'lanche' as MealType,
            p10: 14,
            p90: 16,
            sample_count: 6,
            distinct_day_count: 6,
          },
        ],
      ]),
      totalLogs: 30,
    }
    const r = resolveMealTypeByHour(14, personal)
    expect(r.expected).toBe('almoco')
    expect(r.source).toBe('personal')
  })

  it('span menor ganha: almoco 12-15 (span=3) vs lanche 14-15 (span=1), hora 14 → lanche', () => {
    const personal: PersonalMealWindows = {
      windows: new Map([
        [
          'almoco' as MealType,
          {
            meal_type: 'almoco' as MealType,
            p10: 12,
            p90: 15,
            sample_count: 6,
            distinct_day_count: 6,
          },
        ],
        [
          'lanche' as MealType,
          {
            meal_type: 'lanche' as MealType,
            p10: 14,
            p90: 15,
            sample_count: 6,
            distinct_day_count: 6,
          },
        ],
      ]),
      totalLogs: 30,
    }
    const r = resolveMealTypeByHour(14, personal)
    expect(r.expected).toBe('lanche')
  })

  it('ceia com wrap (p10=23, p90=2), hora 0 → ceia personal', () => {
    const personal: PersonalMealWindows = {
      windows: new Map([
        [
          'ceia' as MealType,
          {
            meal_type: 'ceia' as MealType,
            p10: 23,
            p90: 2,
            sample_count: 6,
            distinct_day_count: 6,
          },
        ],
      ]),
      totalLogs: 30,
    }
    const r = resolveMealTypeByHour(0, personal)
    expect(r.expected).toBe('ceia')
    expect(r.source).toBe('personal')
  })
})

describe('MIN_SAMPLES_FOR_PERSONAL constant exposta', () => {
  it('= 5', () => {
    expect(MIN_SAMPLES_FOR_PERSONAL).toBe(5)
  })
})
