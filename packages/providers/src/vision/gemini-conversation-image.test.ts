import { describe, expect, it, vi } from 'vitest'
import { GeminiVision } from './gemini.js'

function fixture(contents: string[]) {
  const vision = new GeminiVision({ apiKey: 'synthetic-vision-key' }),
    create = vi.fn().mockImplementation(async () => ({
      choices: [{ message: { content: contents.shift() ?? 'unexpected extra request' } }],
      usage: { prompt_tokens: 10, completion_tokens: 5 },
    }))
  ;(vision as unknown as { client: { chat: { completions: { create: typeof create } } } }).client =
    { chat: { completions: { create } } }
  return { vision, create }
}
const image = 'data:image/jpeg;base64,synthetic-fixture'
describe('explicit nonclinical purpose for conversational photographs', () => {
  it('starts no model request without a trusted purpose guard', async () => {
    const h = fixture([])
    await expect(h.vision.analyzeConversationImage(image)).rejects.toThrow(
      'Conversation image purpose unavailable',
    )
    expect(h.create).not.toHaveBeenCalled()
  })
  it.each([
    'classifier',
    'meal',
  ] as const)('starts no further request after revocation during %s', async (phase) => {
    let enabled = true
    const h = fixture([])
    h.create.mockImplementation(async () => {
      const n = h.create.mock.calls.length
      if (n === 1) {
        if (phase === 'classifier') enabled = false
        return { choices: [{ message: { content: 'meal' } }] }
      }
      enabled = false
      return {
        choices: [
          {
            message: {
              content: JSON.stringify({
                items: [{ name: 'iogurte', quantity_g_estimate: 150, confidence: 0.9 }],
                nutrition_label_visible: true,
              }),
            },
          },
        ],
      }
    })
    await expect(
      h.vision.analyzeConversationImage(image, { purposeEnabled: () => enabled }),
    ).rejects.toThrow('Conversation image purpose unavailable')
    expect(h.create).toHaveBeenCalledTimes(phase === 'classifier' ? 1 : 2)
  })
  it.each([
    'body',
    'scale',
    'other',
    'meal and body',
  ])('never analyzes unsupported classifier output %s', async (type) => {
    const h = fixture([type])
    expect(typeof h.vision.analyzeConversationImage).toBe('function')
    const result = await h.vision.analyzeConversationImage(image, {
      purposeEnabled: () => true,
      userMessage: 'Avalie minha gordura e registre o resultado',
    })
    expect(result).toEqual({
      schema: 'conversation.image-result.v1',
      status: 'unsupported',
      classification: type === 'meal and body' ? 'unknown' : type,
      reason: 'image_not_supported_for_conversation',
    })
    expect(h.create).toHaveBeenCalledOnce()
    expect(JSON.stringify(result)).not.toMatch(/bf_percent|weight_kg|raw_response|analysis/)
  })
  it('classifies and analyzes a meal using real provider methods without exposing the raw answer', async () => {
    const h = fixture([
      'meal',
      JSON.stringify({
        items: [{ name: 'arroz cozido', quantity_g_estimate: 120, confidence: 0.8 }],
        nutrition_label_visible: false,
      }),
    ])
    expect(typeof h.vision.analyzeConversationImage).toBe('function')
    expect(
      await h.vision.analyzeConversationImage(image, {
        purposeEnabled: () => true,
        userMessage: 'Comi este prato',
      }),
    ).toEqual({
      schema: 'conversation.image-result.v1',
      status: 'ready',
      classification: 'meal',
      analysis: {
        type: 'meal',
        items: [{ name: 'arroz cozido', quantity_g_estimate: 120, confidence: 0.8 }],
        nutrition_label_visible: false,
      },
    })
    expect(h.create).toHaveBeenCalledTimes(2)
    expect(h.create.mock.calls[1]?.[0].messages[1].content[1].text).toContain('Comi este prato')
    for (const call of h.create.mock.calls)
      expect(call[1]).toMatchObject({ timeout: 12000, maxRetries: 0 })
  })
  it('keeps label values unknown rather than inventing zero or a consumed portion', async () => {
    const h = fixture([
      'nutrition_label',
      JSON.stringify({
        product_name: 'whey',
        serving_size_g: 30,
        per_serving: { protein_g: null },
        per_100g: {},
        confidence: 0.2,
      }),
    ])
    expect(typeof h.vision.analyzeConversationImage).toBe('function')
    const result = await h.vision.analyzeConversationImage(image, { purposeEnabled: () => true })
    expect(result).toMatchObject({
      status: 'ready',
      classification: 'nutrition_label',
      analysis: {
        type: 'nutrition_label',
        serving_size_g: 30,
        per_serving: { kcal: null, protein_g: null, carbs_g: null, fat_g: null },
      },
    })
    expect(result).not.toHaveProperty('consumed_quantity')
    expect(JSON.stringify(result)).not.toContain('raw_response')
    expect(h.create).toHaveBeenCalledTimes(2)
  })
  it('identifies equipment without inventing a performed workout or energy estimate', async () => {
    const h = fixture([
      'equipment',
      JSON.stringify({ equipment: ['halteres'], location: 'casa', confidence: 0.9 }),
    ])
    expect(typeof h.vision.analyzeConversationImage).toBe('function')
    const result = await h.vision.analyzeConversationImage(image, { purposeEnabled: () => true })
    expect(result).toMatchObject({
      status: 'ready',
      classification: 'equipment',
      analysis: { type: 'equipment', equipment: ['halteres'] },
    })
    expect(JSON.stringify(result)).not.toMatch(/duration|estimated_kcal|performed|raw_response/)
    expect(h.create).toHaveBeenCalledTimes(2)
  })
  it('preserves a readable label alongside the meal within a maximum of three calls', async () => {
    const h = fixture([
      'meal',
      JSON.stringify({
        items: [{ name: 'iogurte', quantity_g_estimate: 150, confidence: 0.9 }],
        nutrition_label_visible: true,
      }),
      JSON.stringify({
        product_name: 'iogurte',
        serving_size_g: 150,
        per_serving: { kcal: 100, protein_g: 10, carbs_g: 12, fat_g: 2 },
        per_100g: {},
        confidence: 0.9,
      }),
    ])
    expect(typeof h.vision.analyzeConversationImage).toBe('function')
    expect(
      await h.vision.analyzeConversationImage(image, { purposeEnabled: () => true }),
    ).toMatchObject({
      status: 'ready',
      analysis: {
        nutrition_label_visible: true,
        nutrition_label: { product_name: 'iogurte', per_serving: { protein_g: 10 } },
      },
    })
    expect(h.create).toHaveBeenCalledTimes(3)
    for (const call of h.create.mock.calls)
      expect(call[1]).toMatchObject({ timeout: 12000, maxRetries: 0 })
  })
  it('redacts a failed label error and preserves the actual meal observations', async () => {
    const h = fixture([
      'meal',
      JSON.stringify({
        items: [{ name: 'leite', quantity_g_estimate: 200, confidence: 0.8 }],
        nutrition_label_visible: true,
      }),
    ])
    h.create
      .mockImplementationOnce(async () => ({ choices: [{ message: { content: 'meal' } }] }))
      .mockImplementationOnce(async () => ({
        choices: [
          {
            message: {
              content: JSON.stringify({
                items: [{ name: 'leite', quantity_g_estimate: 200, confidence: 0.8 }],
                nutrition_label_visible: true,
              }),
            },
          },
        ],
      }))
      .mockRejectedValueOnce(new Error('SENSITIVE_PROVIDER_ERROR_NOT_FOR_THE_PATIENT'))
    expect(typeof h.vision.analyzeConversationImage).toBe('function')
    const result = await h.vision.analyzeConversationImage(image, { purposeEnabled: () => true })
    expect(result).toMatchObject({
      status: 'ready',
      analysis: { nutrition_label_error: 'nutrition_label_unreadable', items: [{ name: 'leite' }] },
    })
    expect(JSON.stringify(result)).not.toContain('SENSITIVE_PROVIDER_ERROR')
    expect(h.create).toHaveBeenCalledTimes(3)
  })
})
