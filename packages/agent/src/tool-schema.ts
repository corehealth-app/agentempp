/**
 * Converte ZodSchema para JSON Schema compatível com OpenAI tool calling.
 * Implementação minimal para o subset que usamos (objects, primitivos, enums, arrays).
 */
import { z } from 'zod'

export function zodToJsonSchema(schema: z.ZodTypeAny): Record<string, unknown> {
  return convert(schema)
}

function convert(schema: z.ZodTypeAny): Record<string, unknown> {
  if (schema instanceof z.ZodString) {
    const desc = schema.description
    const out: Record<string, unknown> = { type: 'string' }
    if (desc) out.description = desc
    return out
  }
  if (schema instanceof z.ZodNumber) {
    const checks = (schema._def.checks ?? []) as Array<{ kind: string; value?: number; inclusive?: boolean }>
    const out: Record<string, unknown> = {
      type: checks.some((c) => c.kind === 'int') ? 'integer' : 'number',
    }
    for (const c of checks) {
      if (c.kind === 'min' && c.inclusive !== false && typeof c.value === 'number') out.minimum = c.value
      if (c.kind === 'max' && c.inclusive !== false && typeof c.value === 'number') out.maximum = c.value
    }
    if (schema.description) out.description = schema.description
    return out
  }
  if (schema instanceof z.ZodBoolean) {
    return { type: 'boolean', ...(schema.description ? { description: schema.description } : {}) }
  }
  if (schema instanceof z.ZodEnum) {
    return {
      type: 'string',
      enum: schema.options as string[],
      ...(schema.description ? { description: schema.description } : {}),
    }
  }
  if (schema instanceof z.ZodLiteral) {
    return { const: schema.value }
  }
  if (schema instanceof z.ZodArray) {
    return {
      type: 'array',
      items: convert(schema.element),
      ...(schema.description ? { description: schema.description } : {}),
    }
  }
  // Wrappers keep the inner type (audit 2026-09-29: ZodDefault and ZodEffects
  // fell to the fallback, so the model saw an enum/number/object as a string).
  // Descriptions set on a wrapper stay unshown, as before: surfacing them would
  // change the WhatsApp agent's instructions (adversarial review 2026-09-29).
  if (schema instanceof z.ZodOptional) {
    return convert(schema.unwrap())
  }
  if (schema instanceof z.ZodDefault) {
    const inner = convert(schema._def.innerType)
    const value = schema._def.defaultValue()
    return value === undefined ? inner : { ...inner, default: value }
  }
  if (schema instanceof z.ZodEffects) {
    return convert(schema.innerType())
  }
  if (schema instanceof z.ZodNullable) {
    const inner = convert(schema.unwrap())
    return { ...inner, nullable: true }
  }
  if (schema instanceof z.ZodUnion) {
    return { anyOf: (schema.options as z.ZodTypeAny[]).map((o) => convert(o)) }
  }
  if (schema instanceof z.ZodObject) {
    const shape = schema.shape as Record<string, z.ZodTypeAny>
    const properties: Record<string, unknown> = {}
    const required: string[] = []
    for (const [k, v] of Object.entries(shape)) {
      properties[k] = convert(v)
      if (!(v instanceof z.ZodOptional) && !(v instanceof z.ZodDefault)) {
        required.push(k)
      }
    }
    const out: Record<string, unknown> = { type: 'object', properties }
    if (required.length > 0) out.required = required
    if (schema.description) out.description = schema.description
    return out
  }
  // Fallback genérico
  return { type: 'string' }
}
