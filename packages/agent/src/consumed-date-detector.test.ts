/**
 * Testes do detector determinístico de consumed_date (audit 06-18).
 *
 * Gap descoberto: em 434 chamadas de registra_refeicao desde 2026-05-25,
 * o LLM passou consumed_date ZERO vezes. Detector pré-LLM resolve.
 */
import { describe, expect, it } from 'vitest'
import { detectConsumedDate } from './consumed-date-detector.js'

// Fixar data de referência pra testes determinísticos (sex BRT 2026-06-20 14:00 UTC)
const NOW = new Date('2026-06-20T14:00:00Z')
const TZ = 'America/Sao_Paulo' // -3h → local 11:00 do dia 20

describe('detectConsumedDate', () => {
  it('null/undefined/vazio → null', () => {
    expect(detectConsumedDate(null, TZ, NOW)).toBe(null)
    expect(detectConsumedDate(undefined, TZ, NOW)).toBe(null)
    expect(detectConsumedDate('', TZ, NOW)).toBe(null)
  })

  it('texto sem marcador temporal → null', () => {
    expect(detectConsumedDate('Comi 100g de arroz', TZ, NOW)).toBe(null)
    expect(detectConsumedDate('Almoço com salada', TZ, NOW)).toBe(null)
  })

  // ── Ontem ──────────────────────────────────────────────────────────
  describe('"ontem" patterns', () => {
    it('"isso foi ontem" → days_ago=1', () => {
      const r = detectConsumedDate('isso foi ontem', TZ, NOW)
      expect(r?.days_ago).toBe(1)
      expect(r?.consumed_date).toBe('2026-06-19')
    })

    it('"jantar de ontem" → days_ago=1', () => {
      const r = detectConsumedDate('jantar de ontem foi pizza', TZ, NOW)
      expect(r?.days_ago).toBe(1)
      expect(r?.consumed_date).toBe('2026-06-19')
    })

    it('"comi ontem à noite" → days_ago=1', () => {
      const r = detectConsumedDate('Comi um wrap ontem à noite', TZ, NOW)
      expect(r?.days_ago).toBe(1)
    })

    it('"almoço de ontem" → days_ago=1', () => {
      const r = detectConsumedDate('Esqueci de mandar o almoço de ontem', TZ, NOW)
      expect(r?.days_ago).toBe(1)
    })

    it('"ontem" sozinho (catch-all) → days_ago=1', () => {
      const r = detectConsumedDate('Comi feijoada ontem', TZ, NOW)
      expect(r?.days_ago).toBe(1)
    })

    it('"do dia de ontem" → days_ago=1', () => {
      const r = detectConsumedDate('o registro do dia de ontem', TZ, NOW)
      expect(r?.days_ago).toBe(1)
    })
  })

  // ── Anteontem ──────────────────────────────────────────────────────
  describe('"anteontem" patterns (prioridade > ontem)', () => {
    it('"anteontem" → days_ago=2', () => {
      const r = detectConsumedDate('comi isso anteontem', TZ, NOW)
      expect(r?.days_ago).toBe(2)
      expect(r?.consumed_date).toBe('2026-06-18')
    })

    it('"antes de ontem" → days_ago=2', () => {
      const r = detectConsumedDate('foi antes de ontem', TZ, NOW)
      expect(r?.days_ago).toBe(2)
    })

    it('"há 2 dias" → days_ago=2', () => {
      const r = detectConsumedDate('Comi isso há 2 dias', TZ, NOW)
      expect(r?.days_ago).toBe(2)
    })

    it('texto com "anteontem" E "ontem" → prefere anteontem (mais específico)', () => {
      const r = detectConsumedDate('comi anteontem, e ontem fiz outra coisa', TZ, NOW)
      expect(r?.days_ago).toBe(2)
    })
  })

  // ── NÃO matcha ──────────────────────────────────────────────────────
  describe('NÃO matcha (hoje OU ambíguo)', () => {
    it('"hoje" → null (default da tool já é hoje)', () => {
      expect(detectConsumedDate('Comi hoje', TZ, NOW)).toBe(null)
    })

    it('"essa manhã" → null (hoje implícito)', () => {
      expect(detectConsumedDate('Comi essa manhã', TZ, NOW)).toBe(null)
    })

    it('"amanhã" → null (refeição futura — paciente não registra)', () => {
      expect(detectConsumedDate('vou comer amanhã', TZ, NOW)).toBe(null)
    })
  })

  // ── Hardenings do review adversarial 06-18 ─────────────────────────
  describe('CDD-1: catch-all exige co-ocorrência de lexema alimentar', () => {
    it('"Bom dia, hoje vai ser melhor que ontem" → null (sem comida)', () => {
      expect(detectConsumedDate('Bom dia, hoje vai ser melhor que ontem', TZ, NOW)).toBe(null)
    })

    it('"ontem treinei pesado" → null (treino, não comida)', () => {
      expect(detectConsumedDate('ontem treinei pesado, hoje descanso', TZ, NOW)).toBe(null)
    })

    it('"dormi mal ontem" → null', () => {
      expect(detectConsumedDate('dormi mal ontem', TZ, NOW)).toBe(null)
    })

    it('"comi feijão ontem" → days_ago=1 (lexema "comi" presente)', () => {
      const r = detectConsumedDate('comi feijão ontem', TZ, NOW)
      expect(r?.days_ago).toBe(1)
    })
  })

  describe('CDD-2: negação rejeita match', () => {
    it('"não comi ontem direito" → null', () => {
      expect(detectConsumedDate('não comi ontem direito', TZ, NOW)).toBe(null)
    })

    it('"ontem não jantei" → null', () => {
      expect(detectConsumedDate('ontem não jantei', TZ, NOW)).toBe(null)
    })

    it('"pulei o almoço ontem" → null', () => {
      expect(detectConsumedDate('pulei o almoço ontem', TZ, NOW)).toBe(null)
    })

    it('"esqueci de comer ontem" → null (skip claro)', () => {
      expect(detectConsumedDate('esqueci de comer ontem', TZ, NOW)).toBe(null)
    })

    it('"esqueci de mandar o almoço de ontem" → days_ago=1 (LOGÍSTICA, não skip)', () => {
      // Paciente COMEU, só não reportou. consumed_date=ontem correto.
      const r = detectConsumedDate('esqueci de mandar o almoço de ontem', TZ, NOW)
      expect(r?.days_ago).toBe(1)
    })

    it('"esqueci de registrar o jantar de ontem" → days_ago=1 (logística)', () => {
      const r = detectConsumedDate('esqueci de registrar o jantar de ontem', TZ, NOW)
      expect(r?.days_ago).toBe(1)
    })

    it('"jantei pouco ontem" → days_ago=1 (sem negação)', () => {
      const r = detectConsumedDate('jantei pouco ontem', TZ, NOW)
      expect(r?.days_ago).toBe(1)
    })

    it('"jantar de ontem foi pouco" → days_ago=1 (sem negação, só comentário)', () => {
      const r = detectConsumedDate('jantar de ontem foi pouco mas suficiente', TZ, NOW)
      expect(r?.days_ago).toBe(1)
    })
  })

  describe('CDD-3: não cruza a fronteira entre mensagens do burst', () => {
    it('não empresta o almoço da linha seguinte para "caminhada de ontem"', () => {
      const burst = 'caminhada igual a de ontem \n almoço: arroz e frango'
      expect(detectConsumedDate(burst, TZ, NOW)).toBe(null)
    })

    it('não empresta o jantar da linha seguinte para "ontem treinei"', () => {
      const burst = 'ontem treinei pesado \n jantar com arroz e feijão'
      expect(detectConsumedDate(burst, TZ, NOW)).toBe(null)
    })

    it('não trata "a caminhada foi ontem" como data da refeição seguinte', () => {
      const burst = 'a caminhada foi ontem \n almoço com salada'
      expect(detectConsumedDate(burst, TZ, NOW)).toBe(null)
    })

    it('mantém a detecção quando refeição e marcador estão na mesma mensagem', () => {
      const burst = 'jantar de ontem foi pizza \n segue a foto'
      expect(detectConsumedDate(burst, TZ, NOW)?.days_ago).toBe(1)
    })

    it('mantém o marcador "ontem" quando ele é uma mensagem isolada do burst', () => {
      const burst = 'ontem \n almoço com arroz e feijão'
      expect(detectConsumedDate(burst, TZ, NOW)?.days_ago).toBe(1)
    })
  })

  // ── Timezone ────────────────────────────────────────────────────────
  describe('timezone awareness', () => {
    it('NY (-04 EDT em junho): paciente em NY às 02:00 local = "ontem" recente', () => {
      // NOW=14:00 UTC, NY=-04 → 10:00 local NY do dia 20
      const r = detectConsumedDate('jantar de ontem', 'America/New_York', NOW)
      expect(r?.consumed_date).toBe('2026-06-19')
    })

    it('Tokyo (+09): no momento certo, "ontem" pode ser data diferente', () => {
      // NOW=14:00 UTC → Tokyo 23:00 dia 20 → ontem = 19
      const r = detectConsumedDate('jantar de ontem', 'Asia/Tokyo', NOW)
      expect(r?.consumed_date).toBe('2026-06-19')
    })
  })
})
