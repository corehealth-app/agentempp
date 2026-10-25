import { describe, expect, it, vi } from 'vitest'
import { createReevaluationBodyAnalyzer } from './gemini-reevaluation-photo-analysis'
import { jpegBytes } from './testing/reevaluation-photo-processing-fixtures'

describe('preconfigured recurring body analyzer', () => {
  it('supplies image bytes and body hint without text or requested pose', async () => {
    const analyzeImage = vi
      .fn()
      .mockResolvedValue({ type: 'body', view: 'side', bf_percent_estimate: 20 })
    const analyze = createReevaluationBodyAnalyzer({ analyzeImage })
    const budget = { signal: new AbortController().signal, timeoutMs: 1200 }
    expect(await analyze(jpegBytes(), 'image/jpeg', budget)).toEqual({
      type: 'body',
      view: 'side',
      bf_percent_estimate: 20,
    })
    expect(analyzeImage).toHaveBeenCalledWith(
      `data:image/jpeg;base64,${Buffer.from(jpegBytes()).toString('base64')}`,
      { hint: 'body' },
      { signal: budget.signal, timeout: 1200, maxRetries: 0 },
    )
    expect(analyzeImage).toHaveBeenCalledTimes(1)
  })
})
