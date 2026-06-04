import { describe, expect, it } from 'vitest'
import { routeModel, type ModelRoutingContext } from './model-router.js'

const SONNET = 'anthropic/claude-4.6-sonnet-20260217'
const HAIKU = 'anthropic/claude-4.5-haiku-20251001'

function ctx(overrides: Partial<ModelRoutingContext> = {}): ModelRoutingContext {
  return {
    text: '',
    contentType: 'text',
    stage: 'recomposicao',
    lastInboundContentType: 'text',
    isReentry: false,
    hasOpenPending: false,
    ...overrides,
  }
}

describe('routeModel', () => {
  describe('flag desligada', () => {
    it('nunca rota com flag off', () => {
      const r = routeModel(SONNET, false, ctx({ text: 'ok' }))
      expect(r.model).toBe(SONNET)
      expect(r.changed).toBe(false)
      expect(r.reason).toBe('flag_off')
    })
  })

  describe('mantém Sonnet (defensivo)', () => {
    it('mídia (image) → Sonnet', () => {
      const r = routeModel(SONNET, true, ctx({ contentType: 'image', text: 'foto' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('media_input')
    })

    it('mídia (audio) → Sonnet', () => {
      const r = routeModel(SONNET, true, ctx({ contentType: 'audio' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('media_input')
    })

    it('última inbound foi imagem → Sonnet (contexto foto pendente)', () => {
      const r = routeModel(SONNET, true, ctx({ lastInboundContentType: 'image', text: 'sim' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('recent_media_context')
    })

    it('coleta_dados (onboarding) → Sonnet', () => {
      const r = routeModel(SONNET, true, ctx({ stage: 'coleta_dados', text: 'ok' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('stage_onboarding')
    })

    it('reentry → Sonnet', () => {
      const r = routeModel(SONNET, true, ctx({ isReentry: true, text: 'oi' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('reentry')
    })

    it('pending aberto → Sonnet (correção pode vir)', () => {
      const r = routeModel(SONNET, true, ctx({ hasOpenPending: true, text: 'troca o arroz por batata' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('open_pending')
    })

    it('texto vazio → Sonnet', () => {
      const r = routeModel(SONNET, true, ctx({ text: '' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('empty_text')
    })

    it('texto longo → Sonnet', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'x'.repeat(150) }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('long_text')
    })

    it('texto fala de café → Sonnet', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'no café tomei whey com leite' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('food_workout_keyword')
    })

    it('texto fala de treino → Sonnet', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'fiz 30 min de musculação hoje' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('food_workout_keyword')
    })

    it('texto fala de gramas → Sonnet', () => {
      const r = routeModel(SONNET, true, ctx({ text: '100g de frango' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('food_workout_keyword')
    })

    it('pergunta complexa sem trigger Haiku → Sonnet (default)', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'mas e se eu mudar a meta?' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('no_haiku_match')
    })
  })

  describe('roteia pra Haiku (intents seguras)', () => {
    it('"ok" → Haiku', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'ok' }))
      expect(r.model).toBe(HAIKU)
      expect(r.reason).toBe('trivial_greeting')
    })

    it('"valeu" → Haiku', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'valeu' }))
      expect(r.model).toBe(HAIKU)
    })

    it('"obrigado" → Haiku', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'obrigado' }))
      expect(r.model).toBe(HAIKU)
    })

    it('"👍" emoji → Haiku', () => {
      const r = routeModel(SONNET, true, ctx({ text: '👍' }))
      expect(r.model).toBe(HAIKU)
    })

    it('"bom dia" isolado → Haiku', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'bom dia' }))
      expect(r.model).toBe(HAIKU)
      expect(r.reason).toBe('greeting_opener')
    })

    it('"oi" → Haiku', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'oi' }))
      expect(r.model).toBe(HAIKU)
    })

    it('"quanto kcal hoje?" → Haiku (status question)', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'quanto kcal hoje?' }))
      expect(r.model).toBe(HAIKU)
      expect(r.reason).toBe('status_question')
    })

    it('"qual meu bloco?" → Haiku', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'qual meu bloco?' }))
      expect(r.model).toBe(HAIKU)
    })

    it('"quanto sobrou?" → Haiku', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'quanto sobrou?' }))
      expect(r.model).toBe(HAIKU)
    })
  })

  describe('casos de borda — Sonnet por segurança', () => {
    it('"bom dia, hoje vou tomar whey" → Sonnet (mistura saudação + comida)', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'bom dia, hoje vou tomar whey' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('food_workout_keyword')
    })

    it('"ok, fiz o treino" → Sonnet (mistura ok + treino)', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'ok, fiz o treino' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('food_workout_keyword')
    })

    it('"quanto kcal tem 1 banana?" → Sonnet (pergunta sobre comida)', () => {
      const r = routeModel(SONNET, true, ctx({ text: 'quanto kcal tem 1 banana?' }))
      expect(r.model).toBe(SONNET)
      expect(r.reason).toBe('food_workout_keyword')
    })
  })
})
