/**
 * Reescritor TTS-friendly.
 *
 * Replica o "Agente Audio" do n8n original: pega texto cru e o transforma
 * em um script natural para fala — números por extenso, abreviações
 * expandidas, pausas SSML, primeira pessoa, sem markdown.
 *
 * Implementação: chama um LLM barato (haiku ou flash) com prompt curto.
 * Cache em memória por hash do texto (1h) — frases repetitivas economizam.
 */
import type { OpenRouterLLM } from '../llm/openrouter.js'

const TTS_REWRITER_PROMPT = `Você é um reescritor de textos para Text-to-Speech.
Sua tarefa: transformar o texto fornecido em um script natural para FALA.

Regras:
1. Reescreva em PRIMEIRA pessoa, como se fosse um áudio enviado por WhatsApp.
2. Números por extenso: "150g" → "cento e cinquenta gramas", "2.400 kcal" → "duas mil e quatrocentas calorias".
3. Datas e horas por extenso: "14:30" → "duas e meia da tarde".
4. Abreviações expandidas: "Dr." → "Doutor", "Av." → "Avenida".
5. Remover markdown: ** ** vira ênfase natural, listas viram frases.
6. Adicionar pausas naturais com <break time="0.4s"/> em transições, máximo 3 por parágrafo.
7. Tom informal, próximo, sem soar robótico.
8. NUNCA adicionar conteúdo novo — apenas reformular.
9. Limite: ≤ 600 caracteres no resultado.

Retorne APENAS o texto reescrito, sem prefixos ou comentários.`

interface CacheEntry {
  result: string
  expiresAt: number
}

const cache = new Map<string, CacheEntry>()
const CACHE_TTL_MS = 60 * 60 * 1000 // 1h

function hash(text: string): string {
  let h = 5381
  for (let i = 0; i < text.length; i++) {
    h = (h * 33) ^ text.charCodeAt(i)
  }
  return (h >>> 0).toString(36)
}

export interface RewriteOpts {
  /** Modelo barato pra rewrite. Default: anthropic/claude-haiku-4.5 */
  model?: string
  /** Bypass cache */
  noCache?: boolean
}

export async function rewriteForTTS(
  llm: OpenRouterLLM,
  text: string,
  opts: RewriteOpts = {},
): Promise<string> {
  const trimmed = text.trim()
  if (trimmed.length === 0) return ''
  // Texto curto (≤80 chars sem números/abrev) provavelmente já é falado
  if (trimmed.length <= 80 && !/\d|Dr\.|Av\.|R\$|\*\*|##/.test(trimmed)) {
    return trimmed
  }

  const key = hash(trimmed)

  if (!opts.noCache) {
    const hit = cache.get(key)
    if (hit && hit.expiresAt > Date.now()) {
      return hit.result
    }
  }

  const result = await llm.complete({
    model: opts.model ?? 'anthropic/claude-haiku-4.5',
    systemPrompt: TTS_REWRITER_PROMPT,
    messages: [{ role: 'user', content: trimmed }],
    temperature: 0.3,
    maxTokens: 500,
    metadata: { Stage: 'tts-rewrite' },
  })

  const rewritten = (result.content ?? trimmed).trim()

  cache.set(key, { result: rewritten, expiresAt: Date.now() + CACHE_TTL_MS })

  // Limpa entradas expiradas periodicamente (1% chance)
  if (Math.random() < 0.01) {
    const now = Date.now()
    for (const [k, v] of cache.entries()) {
      if (v.expiresAt < now) cache.delete(k)
    }
  }

  return rewritten
}

/**
 * Helper síncrono: aplica regras determinísticas básicas SEM LLM.
 * Mais barato e rápido para casos simples (cache miss + LLM indisponível).
 */
export function rewriteForTTSDeterministic(text: string): string {
  return text
    .replace(/\*\*(.*?)\*\*/g, '$1')        // remove negrito markdown
    .replace(/\*(.*?)\*/g, '$1')             // remove itálico
    .replace(/^#{1,6}\s+/gm, '')             // remove headers
    .replace(/^[-*+]\s+/gm, '')              // remove bullets
    .replace(/`([^`]+)`/g, '$1')             // remove inline code
    .replace(/\bDr\.\s*/g, 'Doutor ')
    .replace(/\bDra\.\s*/g, 'Doutora ')
    .replace(/\bAv\.\s*/g, 'Avenida ')
    .replace(/\bR\$\s*([\d.,]+)/g, '$1 reais')
    .replace(/(\d+)kg\b/g, '$1 quilos')
    .replace(/(\d+)km\b/g, '$1 quilômetros')
    .replace(/(\d+)kcal\b/g, '$1 calorias')
    .replace(/(\d+)g\b/g, '$1 gramas')
    .replace(/\s+/g, ' ')
    .trim()
}
