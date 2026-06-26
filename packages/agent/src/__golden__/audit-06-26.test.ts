/**
 * Golden tests — Layer 3 pizza-race recovery (audit 06-26).
 *
 * Cenário Luciana 2026-06-23: pending cancelled pelo cancel cego do
 * pipeline + meal_logs subset gravado pelo express path. Tap chega 30-120s
 * depois e antes voltava noop. Agora recupera: DELETE subset + INSERT
 * proposal completa via replace=true.
 *
 * Tests cobrem a LÓGICA do gate (recoveryEligible + threshold subset) sem
 * mock pesado do interactive-handler — replica o predicate localmente pra
 * travar o comportamento esperado.
 */
import { describe, expect, it } from 'vitest'

describe('audit 2026-06-26 — Layer 3 pizza-race recovery', () => {
  const RECOVERY_WINDOW_MS = 120_000

  // Predicate idêntico ao gate em interactive-handler.ts (linhas ~186-205).
  function isRecoveryEligible(opts: {
    action: 'confirm' | 'edit'
    status: 'pending' | 'confirmed' | 'edited' | 'expired' | 'cancelled'
    proposalKind: 'meal' | 'workout' | undefined
    proposalItemsCount: number
    resolvedAt: string | null
    now: number
  }): boolean {
    return (
      opts.action === 'confirm' &&
      opts.status === 'cancelled' &&
      opts.proposalKind === 'meal' &&
      opts.proposalItemsCount >= 2 &&
      typeof opts.resolvedAt === 'string' &&
      opts.now - new Date(opts.resolvedAt).getTime() <= RECOVERY_WINDOW_MS
    )
  }

  describe('gate recoveryEligible', () => {
    const now = new Date('2026-06-26T18:00:00Z').getTime()

    it('cenário REAL Luciana: cancelled + tap 60s depois + pizza 8 itens → ELEGÍVEL', () => {
      expect(
        isRecoveryEligible({
          action: 'confirm',
          status: 'cancelled',
          proposalKind: 'meal',
          proposalItemsCount: 8,
          resolvedAt: new Date(now - 60_000).toISOString(),
          now,
        }),
      ).toBe(true)
    })

    it('tap depois de 120s+ → NÃO elegível (janela curta)', () => {
      expect(
        isRecoveryEligible({
          action: 'confirm',
          status: 'cancelled',
          proposalKind: 'meal',
          proposalItemsCount: 8,
          resolvedAt: new Date(now - 130_000).toISOString(),
          now,
        }),
      ).toBe(false)
    })

    it('action=edit → NÃO elegível', () => {
      expect(
        isRecoveryEligible({
          action: 'edit',
          status: 'cancelled',
          proposalKind: 'meal',
          proposalItemsCount: 8,
          resolvedAt: new Date(now - 60_000).toISOString(),
          now,
        }),
      ).toBe(false)
    })

    it('status=expired/edited/confirmed → NÃO elegível', () => {
      for (const status of ['expired', 'edited', 'confirmed', 'pending'] as const) {
        expect(
          isRecoveryEligible({
            action: 'confirm',
            status,
            proposalKind: 'meal',
            proposalItemsCount: 8,
            resolvedAt: new Date(now - 60_000).toISOString(),
            now,
          }),
        ).toBe(false)
      }
    })

    it('proposalKind=workout → NÃO elegível', () => {
      expect(
        isRecoveryEligible({
          action: 'confirm',
          status: 'cancelled',
          proposalKind: 'workout',
          proposalItemsCount: 8,
          resolvedAt: new Date(now - 60_000).toISOString(),
          now,
        }),
      ).toBe(false)
    })

    it('proposalItemsCount=1 → NÃO elegível (subset não faz sentido)', () => {
      expect(
        isRecoveryEligible({
          action: 'confirm',
          status: 'cancelled',
          proposalKind: 'meal',
          proposalItemsCount: 1,
          resolvedAt: new Date(now - 60_000).toISOString(),
          now,
        }),
      ).toBe(false)
    })

    it('resolved_at=null → NÃO elegível', () => {
      expect(
        isRecoveryEligible({
          action: 'confirm',
          status: 'cancelled',
          proposalKind: 'meal',
          proposalItemsCount: 8,
          resolvedAt: null,
          now,
        }),
      ).toBe(false)
    })
  })

  describe('subset check (80% threshold + sanity kcal 60%)', () => {
    const stripAccents = (s: string) =>
      s.toLowerCase().normalize('NFD').replace(/\p{Diacritic}/gu, '').trim()

    function subsetCheck(
      proposalNames: string[],
      freshLogs: Array<{ food_name: string; kcal: number }>,
      proposalKcalTotal: number,
    ): { ratio: number; sanityOk: boolean; recoveryOk: boolean } {
      const proposalSet = new Set(proposalNames.map(stripAccents))
      let matchCount = 0
      for (const log of freshLogs) {
        if (proposalSet.has(stripAccents(log.food_name))) matchCount++
      }
      const ratio = freshLogs.length > 0 ? matchCount / freshLogs.length : 0
      const subsetKcal = freshLogs.reduce((a, l) => a + l.kcal, 0)
      const sanityOk =
        proposalKcalTotal > 0 ? subsetKcal <= proposalKcalTotal * 0.6 : true
      return {
        ratio,
        sanityOk,
        recoveryOk: freshLogs.length > 0 && ratio >= 0.8 && sanityOk,
      }
    }

    it('Luciana cenário: pizza 8 itens (376 kcal), subset ketchup+maionese (83 kcal) → recovery OK', () => {
      const r = subsetCheck(
        [
          'tortilha de trigo',
          'molho de tomate',
          'frango desfiado',
          'queijo mussarela ralado',
          'tomate fatiado',
          'orégano',
          'ketchup',
          'maionese',
        ],
        [
          { food_name: 'ketchup', kcal: 15 },
          { food_name: 'maionese', kcal: 68 },
        ],
        376,
      )
      expect(r.ratio).toBe(1) // ambos itens estão na proposal
      expect(r.sanityOk).toBe(true) // 83 ≤ 376*0.6=226
      expect(r.recoveryOk).toBe(true)
    })

    it('sanity FAIL: subset kcal > 60% do proposal → NÃO recupera (era refeição independente)', () => {
      const r = subsetCheck(
        ['arroz', 'feijão', 'frango'],
        [
          { food_name: 'arroz', kcal: 200 },
          { food_name: 'feijão', kcal: 100 },
          { food_name: 'frango', kcal: 250 },
        ],
        500,
      )
      // ratio 100% mas subset 550 kcal > 500*0.6=300 → não é subset, é refeição completa
      expect(r.sanityOk).toBe(false)
      expect(r.recoveryOk).toBe(false)
    })

    it('ratio < 80%: 5 logs, 3 batem → 60% → NÃO recupera', () => {
      const r = subsetCheck(
        ['arroz', 'feijão', 'frango', 'salada'],
        [
          { food_name: 'arroz', kcal: 50 },
          { food_name: 'feijão', kcal: 50 },
          { food_name: 'frango', kcal: 50 },
          { food_name: 'pizza', kcal: 50 },
          { food_name: 'hambúrguer', kcal: 50 },
        ],
        500,
      )
      expect(r.ratio).toBe(0.6)
      expect(r.recoveryOk).toBe(false)
    })

    it('normalização acentos: "Açúcar" vs "acucar" match', () => {
      const r = subsetCheck(
        ['Açúcar', 'Café'],
        [
          { food_name: 'acucar', kcal: 10 },
          { food_name: 'cafe', kcal: 5 },
        ],
        100,
      )
      expect(r.ratio).toBe(1)
    })

    it('fresh vazio → NÃO recupera (nada pra deletar)', () => {
      const r = subsetCheck(['arroz', 'feijão'], [], 500)
      expect(r.ratio).toBe(0)
      expect(r.recoveryOk).toBe(false)
    })
  })

  // ── Audit 06-26 review MED 3: Layer 3 mealType inválido aborta recovery ──
  describe('Layer 3 MED 2 — proposal.mealType inválido ABORTA recovery', () => {
    const VALID = ['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'] as const

    function mealTypeOk(raw: unknown): boolean {
      return typeof raw === 'string' && (VALID as readonly string[]).includes(raw)
    }

    it('mealType="lunch" (inglês) → ABORTA (não é da enum)', () => {
      expect(mealTypeOk('lunch')).toBe(false)
    })

    it('mealType=undefined → ABORTA', () => {
      expect(mealTypeOk(undefined)).toBe(false)
    })

    it('mealType="" (string vazia) → ABORTA', () => {
      expect(mealTypeOk('')).toBe(false)
    })

    it('mealType=null → ABORTA (não defaulta cego pra outro)', () => {
      expect(mealTypeOk(null)).toBe(false)
    })

    it('mealType="almoco" válido → SEGUE', () => {
      expect(mealTypeOk('almoco')).toBe(true)
    })

    it('mealType="outro" válido (explicitamente) → SEGUE', () => {
      expect(mealTypeOk('outro')).toBe(true)
    })
  })

  // ── Audit 06-26 review MED 3: Item 5 telemetria mutuamente exclusiva ────
  describe('Item 5 — proposal_msg_id policy: set vs resent', () => {
    // Replicado pra fechar golden — implementação canônica em
    // packages/inngest-functions/src/functions/proposal-msg-id-policy.ts
    function classifyMsgIdEvent(rowWasSet: boolean): string {
      return rowWasSet ? 'pending.interactive_set' : 'pending.interactive_resent'
    }

    it('1º envio (slot vazio) → interactive_set', () => {
      expect(classifyMsgIdEvent(true)).toBe('pending.interactive_set')
    })

    it('re-envio (slot ocupado, .is null falha) → interactive_resent', () => {
      expect(classifyMsgIdEvent(false)).toBe('pending.interactive_resent')
    })

    it('eventos são mutuamente exclusivos', () => {
      expect(classifyMsgIdEvent(true)).not.toBe(classifyMsgIdEvent(false))
    })
  })

  // ── Audit 06-26 review MED 3: Item 3 multimodal gate (foto+áudio) ───────
  describe('Item 3 — gate vision-inflight cobre audio + multimodal', () => {
    function allMediaDone(
      types: ('image' | 'audio')[],
      done: { hasVisionDone: boolean; hasSttDone: boolean },
    ): boolean {
      if (types.includes('image') && !done.hasVisionDone) return false
      if (types.includes('audio') && !done.hasSttDone) return false
      return true
    }

    it('foto+áudio → exige AMBOS done (vision+stt)', () => {
      expect(allMediaDone(['image', 'audio'], { hasVisionDone: true, hasSttDone: true })).toBe(true)
      expect(allMediaDone(['image', 'audio'], { hasVisionDone: true, hasSttDone: false })).toBe(false)
      expect(allMediaDone(['image', 'audio'], { hasVisionDone: false, hasSttDone: true })).toBe(false)
    })

    it('só áudio + stt.transcribed → libera flush', () => {
      expect(allMediaDone(['audio'], { hasVisionDone: false, hasSttDone: true })).toBe(true)
    })
  })

  // ── Audit 06-26 review HIGH 1: NaN guard em progress-calc ───────────────
  describe('Item 1 — NaN/Infinity em dayCredit não corrompe deficitBlock', () => {
    function safeAccumulate(prevDeficit: number, dayCredit: number): number {
      const safe = Number.isFinite(dayCredit) ? dayCredit : 0
      return Math.max(0, Math.round(prevDeficit + safe))
    }

    it('dayCredit=NaN preserva prevDeficit (não corrompe)', () => {
      expect(safeAccumulate(1234, Number.NaN)).toBe(1234)
    })

    it('dayCredit=Infinity → preserva prevDeficit (não vira Infinity no banco)', () => {
      const r = safeAccumulate(500, Number.POSITIVE_INFINITY)
      expect(Number.isFinite(r)).toBe(true)
      expect(r).toBe(500) // prev preservado, Infinity tratado como 0
    })

    it('dayCredit=-Infinity → clampa em 0 (não vira NaN)', () => {
      const r = safeAccumulate(500, Number.NEGATIVE_INFINITY)
      expect(Number.isFinite(r)).toBe(true)
      expect(r).toBe(500)
    })
  })
})
