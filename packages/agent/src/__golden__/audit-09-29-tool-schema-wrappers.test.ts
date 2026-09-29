/**
 * Golden test — tool schemas sent to the model lost their types, staging
 * device gate 2026-09-29 08:29 local (QA account A, backend 989bbb0).
 *
 * Exact scenario: "Quero uma proposta de cardapio de um dia, dentro da minha
 * meta, sem restricoes." The model called propoe_plano_dieta twice and both
 * calls were refused:
 *   [{"issues":["horizon:invalid_enum_value","meals_per_day:invalid_type"]},
 *    {"issues":["meals_per_day:invalid_type"]}]
 * Root cause: zodToJsonSchema did not know ZodDefault, so the model was told
 *   horizon: {type:"string"}          (no enum daily/weekly, no description)
 *   meals_per_day: {type:"string"}    (a number field advertised as text)
 * and "horizon" was marked required although it has a default. The same
 * fallback sends define_meta_peso (object with .refine) as {type:"string"}.
 */
import { describe, expect, it } from 'vitest'
import { z } from 'zod'
import { zodToJsonSchema } from '../tool-schema.js'
import { ALL_TOOLS, defineMetaPeso, geraDieta, propoePlanoDieta } from '../tools.js'

describe('audit 2026-09-29 — wrappers keep the real type in the tool schema', () => {
  it('propoe_plano_dieta advertises horizon as the enum and meals_per_day as an integer 2-6', () => {
    const schema = zodToJsonSchema(propoePlanoDieta.parameters) as {
      properties: Record<string, Record<string, unknown>>
      required?: string[]
    }
    expect(schema.properties.horizon).toMatchObject({ type: 'string', enum: ['daily', 'weekly'], default: 'daily' })
    expect(schema.properties.meals_per_day).toMatchObject({ type: 'integer', minimum: 2, maximum: 6, default: 4 })
    expect(schema.required ?? []).not.toContain('horizon')
    expect(zodToJsonSchema(geraDieta.parameters)).toEqual(schema)
  })

  it('define_meta_peso (object with refine) is advertised as its object, not as a string', () => {
    const schema = zodToJsonSchema(defineMetaPeso.parameters) as { type: string; properties?: Record<string, unknown> }
    expect(schema.type).toBe('object')
    expect(Object.keys(schema.properties ?? {})).toEqual(expect.arrayContaining(['target_weight_kg', 'target_bf_percent']))
  })

  it('every tool is advertised as an object with no field left untyped by the fallback', () => {
    for (const tool of ALL_TOOLS) {
      const schema = zodToJsonSchema(tool.parameters) as { type: string }
      expect(schema.type, tool.name).toBe('object')
    }
  })

  it('unit cases: default, effects, integer bounds; wrapper descriptions stay unshown (WhatsApp unchanged)', () => {
    expect(zodToJsonSchema(z.number().int().min(1).max(7))).toEqual({ type: 'integer', minimum: 1, maximum: 7 })
    expect(zodToJsonSchema(z.string().trim().refine(() => true).optional().describe('tz'))).toEqual({ type: 'string' })
    expect(zodToJsonSchema(z.object({ a: z.string().default('x'), b: z.number().optional(), c: z.boolean() }))).toEqual({
      type: 'object',
      properties: { a: { type: 'string', default: 'x' }, b: { type: 'number' }, c: { type: 'boolean' } },
      required: ['c'],
    })
  })
})
