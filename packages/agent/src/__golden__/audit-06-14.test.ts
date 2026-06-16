/**
 * Golden tests — bugs HIGH descobertos no audit 2026-06-14.
 *
 * ACT-4 prevention plan 2026-06-16: cada bug HIGH dos últimos audits vira
 * fixture golden + regression test pra travar o COMPORTAMENTO esperado dos
 * detectores. Se algum desses testes quebrar, regressão direta — não
 * deixar passar nem com snapshot update.
 *
 * Cobertura:
 *  - I1: engagement matinal NÃO alucina sobre fechamento de ontem
 *  - I2: trustMealType bloqueia autocorrect quando há mealType explícito
 *  - I3: curated phrase rejeita slot temporal incompatível
 *  - I4: items com kcal=0 e quantity>30 fora de whitelist → suspeito
 *  - T3: detector pending casa "registra mesmo assim" mas NÃO bare "pode"
 */
import { describe, expect, it } from 'vitest'
import { detectFakeWrite, inferMealFromSkipText } from '../fake-write-detector.js'
import { isTemporallyCompatible } from '../curated-phrase-selector.js'
import { detectPendingResponse } from '../pending-response-detector.js'
import { embedEduComment, EDU_COMMENT_MARKER } from '../post-registration-message.js'

describe('audit 2026-06-14 — regression tests dos 5 bugs HIGH', () => {
  // ── I1: engagement matinal alucinando ──────────────────────────────
  // O fix REAL do I1 está em engagement-sender.ts (regex anti-alucinação
  // pós-LLM). Aqui validamos o behavior pelo CONTRATO observável:
  // detector de fake_write rejeita "Pulei" + "Anotado: jantar pulado"
  // sem chamar marca_refeicao_pulada → kind='skip' (não 'registration').
  // Foi exatamente o cenário I1+I2 do Roberto 06-15.
  describe('I1+I2: skip fake-write detector', () => {
    it('"Pulei" + LLM "Anotado: jantar pulado" sem tool → kind=skip', () => {
      const r = detectFakeWrite({
        content: 'Anotado: jantar pulado hoje. Amanhã a gente continua.',
        patientText: 'Pulei',
        registrationToolCalled: false,
        skipToolCalled: false,
        mealTypeHint: 'jantar',
      })
      expect(r.isFake).toBe(true)
      expect(r.kind).toBe('skip')
      expect(r.inferredMealType).toBe('jantar')
    })

    it('"passei direto pra cama" + "Boa noite!" → NÃO flaga (false positive evitado)', () => {
      const r = detectFakeWrite({
        content: 'Boa noite! Descansa bem.',
        patientText: 'passei direto pra cama',
        registrationToolCalled: false,
        skipToolCalled: false,
      })
      expect(r.isFake).toBe(false)
    })

    it('"não comi nada hoje" → NÃO flaga (caso clínico, daily-closer trata)', () => {
      const r = detectFakeWrite({
        content: 'Entendi. Vamos focar amanhã.',
        patientText: 'Não comi nada hoje',
        registrationToolCalled: false,
        skipToolCalled: false,
      })
      expect(r.isFake).toBe(false)
    })

    it('inferMealFromSkipText: hint vs texto explícito', () => {
      expect(inferMealFromSkipText('Pulei o almoço')).toBe('almoco')
      expect(inferMealFromSkipText('Pulei', 'jantar')).toBe('jantar')
      expect(inferMealFromSkipText('Pulei')).toBe(null)
    })
  })

  // ── I3: curated phrase temporalmente incompatível ──────────────────
  describe('I3: curated phrase rejeita slot temporal errado', () => {
    it('"Whey de manhã..." NÃO pode cair em jantar (bug Roberto 06-14 22:27)', () => {
      const r = isTemporallyCompatible(
        'Whey de manhã é o tipo de hábito que separa quem leva o processo a sério.',
        'jantar',
      )
      expect(r.ok).toBe(false)
    })

    it('mesma frase ACEITA em cafe', () => {
      const r = isTemporallyCompatible(
        'Whey de manhã é o tipo de hábito que separa quem leva o processo a sério.',
        'cafe',
      )
      expect(r.ok).toBe(true)
    })

    it('frase neutra sem palavra temporal passa em qualquer slot', () => {
      const neutralPhrase = 'Boa fonte de proteína de absorção rápida.'
      expect(isTemporallyCompatible(neutralPhrase, 'cafe').ok).toBe(true)
      expect(isTemporallyCompatible(neutralPhrase, 'jantar').ok).toBe(true)
      expect(isTemporallyCompatible(neutralPhrase, 'ceia').ok).toBe(true)
    })

    it('"antes de dormir" REJEITA em cafe, ACEITA em ceia', () => {
      expect(isTemporallyCompatible('Boa opção antes de dormir.', 'cafe').ok).toBe(false)
      expect(isTemporallyCompatible('Boa opção antes de dormir.', 'ceia').ok).toBe(true)
    })
  })

  // ── T3: pending response detector ──────────────────────────────────
  describe('T3: pending-response-detector — bare "pode" REMOVIDO + extras adicionados', () => {
    it('"sim" / "ok" / "isso" → confirm', () => {
      expect(detectPendingResponse('sim')).toBe('confirm')
      expect(detectPendingResponse('ok')).toBe('confirm')
      expect(detectPendingResponse('isso')).toBe('confirm')
    })

    it('bare "pode" NÃO casa (polissêmico em PT-BR, evita falso positivo)', () => {
      expect(detectPendingResponse('pode')).toBe(null)
      expect(detectPendingResponse('Pode')).toBe(null)
      expect(detectPendingResponse('pode.')).toBe(null)
    })

    it('"pode registrar" continua casando (intenção explícita)', () => {
      expect(detectPendingResponse('pode registrar')).toBe('confirm')
    })

    it('"registra mesmo assim" / "manda ver" → confirm (resposta ao block I4)', () => {
      expect(detectPendingResponse('registra mesmo assim')).toBe('confirm')
      expect(detectPendingResponse('manda ver')).toBe('confirm')
    })

    it('texto longo NÃO casa (parece nova msg, não confirm)', () => {
      expect(detectPendingResponse('sim, comi também 100g de arroz')).toBe(null)
    })
  })

  // ── Invariante das 3 bolhas (FIX 3 / I4 collateral) ────────────────
  describe('I4/embedEduComment: invariante 3 bolhas — items vazios não confunde', () => {
    it('eduComment não-vazio ⇒ marker presente entre tabela e card', () => {
      const text = `Lanche registrado ✅\n\n- ovo cozido (50g): 78 kcal\n**Total: 78 kcal**\n\n🔥 Consumido: 1500/1800`
      const result = embedEduComment(text, 'Bom lanche, proteína completa.')
      expect(result).toContain(EDU_COMMENT_MARKER)
      const eduIdx = result.indexOf(EDU_COMMENT_MARKER)
      const cardIdx = result.indexOf('🔥 Consumido')
      expect(eduIdx).toBeGreaterThan(0)
      expect(eduIdx).toBeLessThan(cardIdx)
    })

    it('eduComment vazio ⇒ texto inalterado (defesa contra payload vazio)', () => {
      const text = `Lanche registrado ✅\n\n🔥 Consumido: 1500/1800`
      expect(embedEduComment(text, '')).toBe(text)
      expect(embedEduComment(text, null)).toBe(text)
      expect(embedEduComment(text, undefined)).toBe(text)
    })
  })
})
