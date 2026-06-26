/**
 * Testes ponta-a-ponta — vision-coverage-checker (audit 06-26 sprint pendentes).
 *
 * Cobre loadRecentVisionAnalyzed + checkCoverage + reportVisionCoverageIfLow
 * com mock Supabase mínimo. Foco em cenários reais:
 *  - 2 fotos batch (mesmo pmid) — caso Roberto 25/06 e 24/06
 *  - Visions já consumidas filtradas por raw_provider_message_id
 *  - Threshold via env var
 *  - Edge cases (sem visions, single vision, overlap completo)
 */
import { describe, expect, it, vi } from 'vitest'
import {
  checkCoverage,
  loadRecentVisionAnalyzed,
  reportVisionCoverageIfLow,
  type RecentVision,
} from './vision-coverage-checker.js'

// Mock minimo do Supabase client (chainable query builder)
function makeMockSupabase(data: {
  visions?: Array<{
    properties: {
      type?: string
      provider_message_id?: string | null
      meal_items?: Array<{ name: string; quantity_g_estimate?: number; confidence?: number }> | null
    }
    occurred_at: string
  }>
  mealLogs?: Array<{ raw_provider_message_id?: string | null }>
  inserts?: Array<{ event: string; properties: unknown }>
}) {
  const inserts = data.inserts ?? []
  return {
    from(table: string) {
      if (table === 'product_events') {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                gte: () => ({
                  order: () => ({
                    limit: () => Promise.resolve({ data: data.visions ?? [], error: null }),
                  }),
                }),
              }),
            }),
          }),
          insert: (row: { event: string; properties: unknown }) => {
            inserts.push(row)
            return Promise.resolve({ data: null, error: null })
          },
        }
      }
      if (table === 'meal_logs') {
        return {
          select: () => ({
            eq: () => ({
              gte: () => Promise.resolve({ data: data.mealLogs ?? [], error: null }),
            }),
          }),
        }
      }
      return { select: () => ({}) }
    },
    _inserts: inserts,
  }
}

describe('vision-coverage-checker', () => {
  // ── loadRecentVisionAnalyzed ─────────────────────────────────────────────
  describe('loadRecentVisionAnalyzed', () => {
    it('retorna apenas visions type=meal com meal_items não-vazio', async () => {
      const supa = makeMockSupabase({
        visions: [
          {
            properties: { type: 'meal', provider_message_id: 'pmid1', meal_items: [{ name: 'arroz' }] },
            occurred_at: '2026-06-25T17:00:00Z',
          },
          {
            properties: { type: 'body', provider_message_id: 'pmid2', meal_items: null },
            occurred_at: '2026-06-25T16:00:00Z',
          },
          {
            properties: { type: 'meal', provider_message_id: 'pmid3', meal_items: [] },
            occurred_at: '2026-06-25T15:00:00Z',
          },
        ],
      })
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const result = await loadRecentVisionAnalyzed(supa as any, 'user-1', 30)
      expect(result).toHaveLength(1)
      expect(result[0]?.provider_message_id).toBe('pmid1')
    })

    it('lista vazia → retorna array vazio', async () => {
      const supa = makeMockSupabase({ visions: [] })
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const result = await loadRecentVisionAnalyzed(supa as any, 'user-1', 30)
      expect(result).toEqual([])
    })
  })

  // ── checkCoverage ────────────────────────────────────────────────────────
  describe('checkCoverage — cenários reais Roberto', () => {
    it('Roberto 25/06: 2 fotos = 9 items, tool_call só 4 do prato → ratio 33%', () => {
      const visions: RecentVision[] = [
        {
          provider_message_id: 'pmid_prato',
          items: [
            { name: 'arroz branco cozido' },
            { name: 'feijão cozido' },
            { name: 'carne frita empanada' },
            { name: 'farofa' },
          ],
          occurred_at: '2026-06-25T17:09:46Z',
        },
        {
          provider_message_id: 'pmid_salada',
          items: [
            { name: 'alface crespa' },
            { name: 'cenoura ralada' },
            { name: 'milho verde' },
            { name: 'tomate cereja' },
            { name: 'molho rosado' },
          ],
          occurred_at: '2026-06-25T17:09:46Z',
        },
      ]
      const toolCall = [
        { food_name: 'arroz branco cozido' },
        { food_name: 'feijão cozido' },
        { food_name: 'carne de porco cozida' },
        { food_name: 'farofa' },
      ]
      const report = checkCoverage(visions, toolCall)
      expect(report.vision_items_count).toBe(9)
      expect(report.overlap_ratio).toBeCloseTo(3 / 9, 2)
      expect(report.missing_from_tool_call).toContain('alface crespa')
      expect(report.missing_from_tool_call).toContain('molho rosado')
      expect(report.pmids_checked).toContain('pmid_salada')
    })

    it('Roberto 24/06: 9 items vision, só 4 prato registrado → ratio baixo', () => {
      const visions: RecentVision[] = [
        {
          provider_message_id: 'pmid_22',
          items: [
            { name: 'arroz' },
            { name: 'feijão' },
            { name: 'farofa' },
            { name: 'porco' },
          ],
          occurred_at: '2026-06-24T17:00:00Z',
        },
        {
          provider_message_id: 'pmid_22',
          items: [
            { name: 'alface' },
            { name: 'cenoura' },
            { name: 'milho' },
            { name: 'tomate' },
            { name: 'molho' },
          ],
          occurred_at: '2026-06-24T17:00:00Z',
        },
      ]
      const toolCall = [
        { food_name: 'arroz' },
        { food_name: 'feijão' },
        { food_name: 'farofa' },
        { food_name: 'porco' },
      ]
      const report = checkCoverage(visions, toolCall)
      expect(report.overlap_ratio).toBeLessThan(0.7)
    })

    it('cobertura completa (foto única bem registrada) → ratio 1, sem missing', () => {
      const visions: RecentVision[] = [
        {
          provider_message_id: 'pmid1',
          items: [{ name: 'arroz' }, { name: 'feijão' }],
          occurred_at: '2026-06-25T17:00:00Z',
        },
      ]
      const toolCall = [{ food_name: 'arroz' }, { food_name: 'feijão' }]
      const report = checkCoverage(visions, toolCall)
      expect(report.overlap_ratio).toBe(1)
      expect(report.missing_from_tool_call).toEqual([])
    })

    it('normaliza acentos: "Açúcar" vs "acucar" matcha', () => {
      const visions: RecentVision[] = [
        {
          provider_message_id: 'pmid1',
          items: [{ name: 'Açúcar' }, { name: 'Café com Leite' }],
          occurred_at: '2026-06-25T17:00:00Z',
        },
      ]
      const toolCall = [{ food_name: 'acucar' }, { food_name: 'cafe com leite' }]
      const report = checkCoverage(visions, toolCall)
      expect(report.overlap_ratio).toBe(1)
    })

    it('vision vazia → ratio 1 (sem alerta)', () => {
      const report = checkCoverage([], [{ food_name: 'qualquer' }])
      expect(report.overlap_ratio).toBe(1)
      expect(report.vision_items_count).toBe(0)
    })

    it('tool_call vazio mas vision tem items → ratio 0', () => {
      const visions: RecentVision[] = [
        {
          provider_message_id: 'pmid1',
          items: [{ name: 'arroz' }, { name: 'feijão' }],
          occurred_at: '2026-06-25T17:00:00Z',
        },
      ]
      const report = checkCoverage(visions, [])
      expect(report.overlap_ratio).toBe(0)
      expect(report.missing_from_tool_call).toHaveLength(2)
    })
  })

  // ── reportVisionCoverageIfLow ───────────────────────────────────────────
  describe('reportVisionCoverageIfLow', () => {
    it('emite warning quando overlap < threshold E vision_items >= 3', async () => {
      const supa = makeMockSupabase({
        visions: [
          {
            properties: {
              type: 'meal',
              provider_message_id: 'pmid_uncovered',
              meal_items: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }],
            },
            occurred_at: '2026-06-25T17:00:00Z',
          },
        ],
        mealLogs: [], // nenhum consumed
      })
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const report = await reportVisionCoverageIfLow(supa as any, 'user-1', [{ food_name: 'x' }])
      expect(report).not.toBeNull()
      expect(report!.overlap_ratio).toBe(0)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const inserts = (supa as any)._inserts
      expect(inserts).toHaveLength(1)
      expect(inserts[0].event).toBe('pipeline.vision_coverage_warning')
    })

    it('NÃO emite quando vision_items < 3 (não alerta perda pequena)', async () => {
      const supa = makeMockSupabase({
        visions: [
          {
            properties: { type: 'meal', provider_message_id: 'pmid_small', meal_items: [{ name: 'a' }, { name: 'b' }] },
            occurred_at: '2026-06-25T17:00:00Z',
          },
        ],
        mealLogs: [],
      })
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await reportVisionCoverageIfLow(supa as any, 'user-1', [{ food_name: 'x' }])
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      expect((supa as any)._inserts).toHaveLength(0)
    })

    it('filtra visions já consumidas (pmid match em meal_logs) — review HIGH 5', async () => {
      const supa = makeMockSupabase({
        visions: [
          {
            properties: {
              type: 'meal',
              provider_message_id: 'pmid_consumed',
              meal_items: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }],
            },
            occurred_at: '2026-06-25T17:00:00Z',
          },
        ],
        // Já registrada com o mesmo pmid — não deve gerar warning
        mealLogs: [{ raw_provider_message_id: 'pmid_consumed' }],
      })
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const report = await reportVisionCoverageIfLow(supa as any, 'user-1', [{ food_name: 'x' }])
      expect(report).toBeNull() // pendingVisions vazia → null
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      expect((supa as any)._inserts).toHaveLength(0)
    })

    it('NÃO emite quando overlap >= threshold (cobertura boa)', async () => {
      const supa = makeMockSupabase({
        visions: [
          {
            properties: {
              type: 'meal',
              provider_message_id: 'pmid_covered',
              meal_items: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }],
            },
            occurred_at: '2026-06-25T17:00:00Z',
          },
        ],
        mealLogs: [],
      })
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await reportVisionCoverageIfLow(supa as any, 'user-1', [
        { food_name: 'a' },
        { food_name: 'b' },
        { food_name: 'c' },
        { food_name: 'd' },
      ])
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      expect((supa as any)._inserts).toHaveLength(0)
    })

    it('sem visions → retorna null sem emitir', async () => {
      const supa = makeMockSupabase({ visions: [] })
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const report = await reportVisionCoverageIfLow(supa as any, 'user-1', [{ food_name: 'x' }])
      expect(report).toBeNull()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      expect((supa as any)._inserts).toHaveLength(0)
    })

    // Audit 06-26 review LOW: env var override do threshold.
    it('threshold custom via VISION_COVERAGE_THRESHOLD env var → respeitado em chamada explícita', async () => {
      vi.stubEnv('VISION_COVERAGE_THRESHOLD', '0.5')
      try {
        // Re-import dinâmico pra pegar env atualizado
        const mod = await import('./vision-coverage-checker.js')
        // Tem 4 items vision, 2 cobertos = ratio 50%. Default 0.7 alertaria;
        // com threshold=0.5, NÃO alerta (porque ratio NÃO é < 0.5).
        const supa = makeMockSupabase({
          visions: [
            {
              properties: {
                type: 'meal',
                provider_message_id: 'pmid_half',
                meal_items: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }],
              },
              occurred_at: '2026-06-26T17:00:00Z',
            },
          ],
          mealLogs: [],
        })
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await mod.reportVisionCoverageIfLow(supa as any, 'user-1', [
          { food_name: 'a' },
          { food_name: 'b' },
        ])
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        expect((supa as any)._inserts).toHaveLength(0)
      } finally {
        vi.unstubAllEnvs()
      }
    })

    it('threshold inválido (>1 / NaN / negativo) cai pro default 0.7', async () => {
      const supa = makeMockSupabase({
        visions: [
          {
            properties: {
              type: 'meal',
              provider_message_id: 'pmid_x',
              meal_items: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }],
            },
            occurred_at: '2026-06-26T17:00:00Z',
          },
        ],
        mealLogs: [],
      })
      for (const bad of ['abc', '-0.5', '1.5']) {
        vi.stubEnv('VISION_COVERAGE_THRESHOLD', bad)
        try {
          const mod = await import('./vision-coverage-checker.js')
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          await mod.reportVisionCoverageIfLow(supa as any, 'user-1', [{ food_name: 'a' }])
          // Default 0.7 → 1/4=0.25 < 0.7 → DEVE emitir warning
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          expect((supa as any)._inserts.length).toBeGreaterThan(0)
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          ;(supa as any)._inserts.length = 0
        } finally {
          vi.unstubAllEnvs()
        }
      }
    })
  })
})
