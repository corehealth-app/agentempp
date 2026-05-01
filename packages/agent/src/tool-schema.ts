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
    const out: Record<string, unknown> = { type: 'number' }
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
  if (schema instanceof z.ZodOptional) {
    return convert(schema.unwrap())
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
      if (!(v instanceof z.ZodOptional)) {
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
