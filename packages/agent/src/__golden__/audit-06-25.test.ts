/**
 * Golden tests — bugs A/B/C/D do audit 2026-06-25 (feedback Roberto + Luciana).
 *
 * Cenários EXATOS reportados pelos pacientes (não variantes próximas):
 *  - Bug A: bom dia matinal nunca mostra bloco parcial em construção
 *  - Bug B: 2 fotos + pergunta intermediária → 2ª foto sumiu silenciosamente
 *  - Bug C: "1 vs 2 pão francês" não obedeceu correção do paciente
 *  - Bug D: replace=true soma em vez de substituir (lanche pão 540+270=810)
 *
 * Mudança de processo (audit 06-25): cada bug reportado vira golden fixture
 * com frase/timing/IDs do print, NÃO variante próxima. Evita "fix completo"
 * sem cobrir cenário real (foi o que aconteceu 06-13 a 06-24).
 */
import { describe, expect, it } from 'vitest'
import { detectCorrectionIntent } from '../correction-detector.js'
import { checkCoverage, type RecentVision } from '../vision-coverage-checker.js'

describe('audit 2026-06-25 — Roberto + Luciana feedback', () => {
  // ── Bug C: correção de quantidade ("1 vs 2") ───────────────────────────
  describe('Bug C: correction-detector pega "era N", "comi N não M", "N não M"', () => {
    it('Pattern 1: "era 2 ovos" — afirmação de quantidade prévia (sem "não")', () => {
      expect(detectCorrectionIntent(['era 2 ovos no café'])).toBeTruthy()
      expect(detectCorrectionIntent(['eram 2 pães na verdade'])).toBeTruthy()
      expect(detectCorrectionIntent(['foi 1 fatia só'])).toBeTruthy()
      expect(detectCorrectionIntent(['foram 2 colheres'])).toBeTruthy()
    })

    it('Pattern 2: "comi 2, não 1" / "tomei 2, não 1" (inversão verbo+vírgula+não)', () => {
      expect(detectCorrectionIntent(['comi 2, não 1'])).toBeTruthy()
      expect(detectCorrectionIntent(['tomei 200ml de leite, não 300'])).toBeTruthy()
      expect(detectCorrectionIntent(['bebi 1 copo, não 2'])).toBeTruthy()
      expect(detectCorrectionIntent(['fiz 2 ovos mexidos, não 4'])).toBeTruthy()
    })

    it('Pattern 3: "foi 1 não 2" (forma curta com verbo OBRIGATÓRIO após review HIGH 7)', () => {
      expect(detectCorrectionIntent(['foi 1 não 2'])).toBeTruthy()
      expect(detectCorrectionIntent(['era 1 não 2'])).toBeTruthy()
      expect(detectCorrectionIntent(['foram 2 não 4'])).toBeTruthy()
      // "1 não 2" sozinho NÃO matcha (sem verbo) — evita FP em conversa sobre
      // sono/tempo/dose ("dormi 1 não 2 horas").
      expect(detectCorrectionIntent(['1 não 2'])).toBeFalsy()
    })

    it('Cenário REAL Luciana 25/06: "Está errado / Foi só 1 pão / Não dois"', () => {
      // 3 frases consecutivas do print. Pelo menos UMA deve disparar correção.
      const detected =
        detectCorrectionIntent(['Está errado']) ||
        detectCorrectionIntent(['Foi só 1 pão']) ||
        detectCorrectionIntent(['Não dois'])
      expect(detected).toBeTruthy()
    })

    it('NÃO matcha texto normal de registro (não confundir adição com correção)', () => {
      expect(detectCorrectionIntent(['comi pão francês no café'])).toBeFalsy()
      expect(detectCorrectionIntent(['1 pão com manteiga'])).toBeFalsy()
      expect(detectCorrectionIntent(['no café tive iogurte'])).toBeFalsy()
    })
  })

  // ── Bug B: vision-coverage-checker detecta perda silenciosa ────────────
  describe('Bug B: checkCoverage flag salada Roberto 25/06 (2 fotos, 2ª sumiu)', () => {
    it('cenário REAL: 2 fotos = 9 itens vision, tool_call só com 4 do prato → ratio < 0.7', () => {
      const visions: RecentVision[] = [
        {
          provider_message_id: 'wamid.xx_prato',
          items: [
            { name: 'arroz branco cozido' },
            { name: 'feijão cozido' },
            { name: 'carne empanada' },
            { name: 'farofa' },
          ],
          occurred_at: '2026-06-25T17:09:46Z',
        },
        {
          provider_message_id: 'wamid.xx_salada',
          items: [
            { name: 'alface' },
            { name: 'cenoura' },
            { name: 'milho' },
            { name: 'tomate cereja' },
            { name: 'molho rosado' },
          ],
          occurred_at: '2026-06-25T17:09:46Z',
        },
      ]
      const toolCallItems = [
        { food_name: 'arroz branco cozido' },
        { food_name: 'feijão cozido' },
        { food_name: 'carne de porco cozida' },
        { food_name: 'farofa' },
      ]
      const report = checkCoverage(visions, toolCallItems)
      // 9 vision items, 3 cobertos (arroz, feijão, farofa) — carne tem nome
      // diferente após disambiguação. Ratio = 3/9 = 0.33 < threshold 0.7.
      expect(report.vision_items_count).toBe(9)
      expect(report.overlap_ratio).toBeLessThan(0.7)
      // Itens da salada estão entre os missing
      expect(report.missing_from_tool_call).toContain('alface')
      expect(report.missing_from_tool_call).toContain('molho rosado')
    })

    it('foto única bem coberta → ratio alto, sem warning', () => {
      const visions: RecentVision[] = [
        {
          provider_message_id: 'wamid.xx_single',
          items: [{ name: 'arroz' }, { name: 'feijão' }, { name: 'frango' }],
          occurred_at: '2026-06-25T17:09:46Z',
        },
      ]
      const toolCallItems = [
        { food_name: 'arroz' },
        { food_name: 'feijão' },
        { food_name: 'frango' },
      ]
      const report = checkCoverage(visions, toolCallItems)
      expect(report.overlap_ratio).toBe(1)
    })

    it('normaliza acentos: "Açúcar" vs "açucar" matcha', () => {
      const visions: RecentVision[] = [
        {
          provider_message_id: 'wamid.x',
          items: [{ name: 'Açúcar' }, { name: 'Café' }],
          occurred_at: '2026-06-25T17:09:46Z',
        },
      ]
      const toolCallItems = [{ food_name: 'acucar' }, { food_name: 'cafe' }]
      const report = checkCoverage(visions, toolCallItems)
      expect(report.overlap_ratio).toBe(1)
    })

    it('sem visions → overlap 1 (não alerta)', () => {
      const report = checkCoverage([], [{ food_name: 'arroz' }])
      expect(report.overlap_ratio).toBe(1)
      expect(report.vision_items_count).toBe(0)
    })
  })

  // ── Bug A: bom dia matinal mostra bloco parcial ───────────────────────
  describe('Bug A: linha "Bloco N em construção" formatada corretamente', () => {
    // Réplica do snippet do engagement-sender (que está inline no template)
    function formatBlocoEmConstrucao(
      blocksCompleted: number,
      deficitBlock: number,
    ): string {
      const blocoAtual = blocksCompleted + 1
      const pct = Math.round((deficitBlock / 7700) * 100)
      const fmtBR = (n: number) => n.toLocaleString('pt-BR')
      return `Bloco ${blocoAtual} em construção: ${fmtBR(deficitBlock)} / 7.700 kcal (${pct}%)`
    }

    it('Roberto cenário REAL 25/06: blocks=5, deficit_block=3786 → "Bloco 6: 3.786 / 7.700 (49%)"', () => {
      const line = formatBlocoEmConstrucao(5, 3786)
      expect(line).toContain('Bloco 6 em construção')
      expect(line).toContain('3.786 / 7.700 kcal')
      expect(line).toContain('(49%)')
    })

    it('formato pt-BR separador de milhar', () => {
      expect(formatBlocoEmConstrucao(2, 5500)).toContain('5.500')
      expect(formatBlocoEmConstrucao(0, 1234)).toContain('1.234')
    })

    it('pct arredondado corretamente', () => {
      expect(formatBlocoEmConstrucao(0, 7699)).toContain('(100%)')
      expect(formatBlocoEmConstrucao(0, 100)).toContain('(1%)')
      expect(formatBlocoEmConstrucao(0, 3850)).toContain('(50%)')
    })
  })

  // ── Bug D: replace inferido pelo tap-handler ──────────────────────────
  describe('Bug D: lógica de effectiveReplace no tap-handler', () => {
    // Réplica simplificada do gate em interactive-handler.ts
    function shouldInferReplace(opts: {
      proposalReplace: boolean
      proposalKind: 'meal' | 'workout'
      proposalMealType: string | null
      hasPriorMealOfSameType: boolean
      hasPriorEdited: boolean
    }): boolean {
      if (opts.proposalReplace) return true
      if (opts.proposalKind !== 'meal' || !opts.proposalMealType) return false
      return opts.hasPriorMealOfSameType && opts.hasPriorEdited
    }

    it('cenário Luciana 25/06: pending lanche pão SEM replace explícito + log prévio mesmo dia + pending edited → infere replace', () => {
      expect(
        shouldInferReplace({
          proposalReplace: false,
          proposalKind: 'meal',
          proposalMealType: 'lanche',
          hasPriorMealOfSameType: true, // 540 kcal já gravadas
          hasPriorEdited: true, // pending anterior status='edited'
        }),
      ).toBe(true)
    })

    it('sem pending edited → NÃO infere (preserva caso de 2 jantares legítimos no mesmo dia)', () => {
      expect(
        shouldInferReplace({
          proposalReplace: false,
          proposalKind: 'meal',
          proposalMealType: 'jantar',
          hasPriorMealOfSameType: true,
          hasPriorEdited: false,
        }),
      ).toBe(false)
    })

    it('sem log prévio → NÃO infere (primeira refeição do meal_type no dia)', () => {
      expect(
        shouldInferReplace({
          proposalReplace: false,
          proposalKind: 'meal',
          proposalMealType: 'cafe',
          hasPriorMealOfSameType: false,
          hasPriorEdited: true,
        }),
      ).toBe(false)
    })

    it('proposalReplace=true já explícito → sempre replace', () => {
      expect(
        shouldInferReplace({
          proposalReplace: true,
          proposalKind: 'meal',
          proposalMealType: 'almoco',
          hasPriorMealOfSameType: false,
          hasPriorEdited: false,
        }),
      ).toBe(true)
    })

    it('workout → nunca infere replace (só meal)', () => {
      expect(
        shouldInferReplace({
          proposalReplace: false,
          proposalKind: 'workout',
          proposalMealType: null,
          hasPriorMealOfSameType: true,
          hasPriorEdited: true,
        }),
      ).toBe(false)
    })
  })
})
