/**
 * Humanizador de mensagens — replica o comportamento do n8n original.
 *
 * Quebra texto longo em chunks por \n\n e envia com delay proporcional
 * ao tamanho do chunk. Simula tempo de digitação humana.
 *
 * Limites:
 *  - mínimo 800ms entre chunks
 *  - máximo 4s entre chunks
 *  - chunks com >280 chars são divididos em sub-chunks por sentença
 */
import type { MessagingProvider, SendOpts, SendResult } from './types.js'

export interface HumanizeOpts {
  /** Atraso mínimo em ms (default 800) */
  minDelay?: number
  /** Atraso máximo em ms (default 4000) */
  maxDelay?: number
  /** Caracteres por segundo de "digitação" simulada (default 50 = ~human fast) */
  charsPerSecond?: number
  /** Mostrar typing indicator entre chunks (default true) */
  showTyping?: boolean
}

const DEFAULT_OPTS: Required<HumanizeOpts> = {
  minDelay: 800,
  maxDelay: 4000,
  charsPerSecond: 50,
  showTyping: true,
}

/**
 * Quebra texto em chunks naturais.
 * Estratégia: split por \n\n. Se chunk > 280 chars, sub-divide por sentença (. ! ?).
 */
export function chunkMessage(text: string, maxChars = 280): string[] {
  const paragraphs = text
    .split(/\n\n+/)
    .map((p) => p.trim())
    .filter(Boolean)

  const chunks: string[] = []
  for (const p of paragraphs) {
    if (p.length <= maxChars) {
      chunks.push(p)
      continue
    }
    // Sub-divide por sentença
    const sentences = p.match(/[^.!?]+[.!?]+|[^.!?]+$/g) ?? [p]
    let current = ''
    for (const s of sentences) {
      const trimmed = s.trim()
      if ((current + ' ' + trimmed).trim().length > maxChars) {
        if (current) chunks.push(current.trim())
        current = trimmed
      } else {
        current = current ? `${current} ${trimmed}` : trimmed
      }
    }
    if (current) chunks.push(current.trim())
  }
  return chunks.length > 0 ? chunks : [text]
}

/**
 * Calcula delay para um chunk específico.
 */
export function delayForChunk(chunk: string, opts: Required<HumanizeOpts>): number {
  const ms = (chunk.length / opts.charsPerSecond) * 1000
  return Math.min(opts.maxDelay, Math.max(opts.minDelay, ms))
}

interface SendHumanizedExtra {
  /** ID da última msg recebida do user — usado p/ typing indicator real do WhatsApp */
  inReplyTo?: string
}

/**
 * Envia uma mensagem ao usuário em modo humanizado:
 *   1. Quebra em chunks por \n\n
 *   2. (opcional) showTypingFor(inReplyTo) ANTES do primeiro chunk — único typing real
 *   3. Para cada chunk: delay proporcional → sendText (1º com replyTo)
 *   4. Pequeno gap entre chunks
 */
export async function sendHumanized(
  provider: MessagingProvider,
  to: string,
  text: string,
  opts?: HumanizeOpts & SendOpts & SendHumanizedExtra,
): Promise<SendResult[]> {
  const config = { ...DEFAULT_OPTS, ...opts }
  const chunks = chunkMessage(text)
  const results: SendResult[] = []

  // Typing indicator real só é possível 1× (Cloud API). Mostra antes do 1º chunk.
  if (config.showTyping && opts?.inReplyTo && provider.showTypingFor) {
    await provider.showTypingFor(opts.inReplyTo).catch(() => {})
  }

  for (let i = 0; i < chunks.length; i++) {
    const chunk = chunks[i]
    if (!chunk) continue

    await sleep(delayForChunk(chunk, config))

    // Só o primeiro chunk pode usar quoted reply
    const sendOpts: SendOpts | undefined =
      i === 0 && opts?.replyTo ? { replyTo: opts.replyTo } : undefined
    const result = await provider.sendText(to, chunk, sendOpts)
    results.push(result)

    if (i < chunks.length - 1) {
      await sleep(300)
    }
  }
  return results
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
