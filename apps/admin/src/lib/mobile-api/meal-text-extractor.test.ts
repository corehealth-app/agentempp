import { describe, expect, it } from 'vitest'
import { parseMealExtractionContent } from './meal-text-extractor'

// Anthropic models reached through OpenRouter do not honour json_object and
// often wrap the answer in a Markdown fence. The fence is not a failure.
describe('parseMealExtractionContent', () => {
  const body = '{"items":[{"name":"café","count":null,"unit":null,"grams_stated":null}]}'

  it('reads a bare JSON object', () => {
    expect(parseMealExtractionContent(body)).toEqual(JSON.parse(body))
  })

  it('reads a JSON object wrapped in a ```json fence', () => {
    expect(parseMealExtractionContent('```json\n' + body + '\n```')).toEqual(JSON.parse(body))
  })

  it('reads a JSON object wrapped in a bare ``` fence with surrounding whitespace', () => {
    expect(parseMealExtractionContent('\n```\n' + body + '\n```\n')).toEqual(JSON.parse(body))
  })

  it('reads a one-line fence and a jsonc fence', () => {
    expect(parseMealExtractionContent('```json ' + body + '```')).toEqual(JSON.parse(body))
    expect(parseMealExtractionContent('```jsonc\n' + body + '\n```')).toEqual(JSON.parse(body))
  })

  it('a cut answer (finish_reason length) is reported as truncated, not as invalid JSON', () => {
    expect(() => parseMealExtractionContent('{"items":[{"name":"ca', 'length')).toThrow(
      expect.objectContaining({ code: 'truncated' }),
    )
  })

  it('refuses empty content with a stable code', () => {
    expect(() => parseMealExtractionContent(null)).toThrow(
      expect.objectContaining({ name: 'MealExtractionContentError', code: 'empty_content' }),
    )
    expect(() => parseMealExtractionContent('   ')).toThrow(
      expect.objectContaining({ code: 'empty_content' }),
    )
  })

  it('refuses prose instead of guessing an object out of it', () => {
    expect(() => parseMealExtractionContent('Você comeu café e pão.')).toThrow(
      expect.objectContaining({ code: 'invalid_json' }),
    )
    expect(() => parseMealExtractionContent('Aqui está: {"items":[]}')).toThrow(
      expect.objectContaining({ code: 'invalid_json' }),
    )
  })
})
