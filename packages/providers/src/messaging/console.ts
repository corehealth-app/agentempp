/**
 * ConsoleProvider — simula o WhatsApp Cloud API para desenvolvimento local.
 *
 * Saídas: console.log com prefixo colorido.
 * Entradas: o caller (ex: CLI) chama `parseInbound(text, from)` manualmente.
 */
import type {
  HSMTemplate,
  MessagingProvider,
  NormalizedInbound,
  QualityStatus,
  SendOpts,
  SendResult,
} from './types.js'

interface ConsoleProviderConfig {
  /** Prefixo na saída (default '[mpp]'). */
  prefix?: string
  /** Habilita cores ANSI. */
  color?: boolean
  /** Capturar saída em buffer ao invés de escrever no stdout. */
  captureOutput?: boolean
}

const ANSI = {
  reset: '\x1b[0m',
  dim: '\x1b[2m',
  bold: '\x1b[1m',
  green: '\x1b[32m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  yellow: '\x1b[33m',
  magenta: '\x1b[35m',
}

let counter = 0

export class ConsoleProvider implements MessagingProvider {
  readonly name = 'console'
  readonly outputBuffer: string[] = []

  constructor(private cfg: ConsoleProviderConfig = {}) {}

  private color(s: string, c: keyof typeof ANSI): string {
    if (this.cfg.color === false) return s
    return `${ANSI[c]}${s}${ANSI.reset}`
  }

  private write(line: string) {
    if (this.cfg.captureOutput) this.outputBuffer.push(line)
    else process.stdout.write(`${line}\n`)
  }

  private newId(): string {
    return `console_${Date.now()}_${++counter}`
  }

  async sendText(to: string, text: string, _opts?: SendOpts): Promise<SendResult> {
    const id = this.newId()
    this.write(
      `\n${this.color('🤖 Agente →', 'green')} ${this.color(to, 'dim')}\n${text}\n`,
    )
    return { providerMessageId: id, status: 'sent' }
  }

  async sendAudio(to: string, audioUrl: string): Promise<SendResult> {
    const id = this.newId()
    this.write(
      `\n${this.color('🎙️ Agente (áudio) →', 'magenta')} ${this.color(to, 'dim')}\n${this.color(audioUrl, 'dim')}\n`,
    )
    return { providerMessageId: id, status: 'sent' }
  }

  async sendImage(to: string, url: string, caption?: string): Promise<SendResult> {
    const id = this.newId()
    this.write(
      `\n${this.color('🖼️ Agente (imagem) →', 'cyan')} ${this.color(to, 'dim')}\n${url}${caption ? `\n${caption}` : ''}\n`,
    )
    return { providerMessageId: id, status: 'sent' }
  }

  async sendTemplate(to: string, template: HSMTemplate): Promise<SendResult> {
    const id = this.newId()
    const vars = Object.entries(template.variables)
      .map(([k, v]) => `  ${k}: ${v}`)
      .join('\n')
    this.write(
      `\n${this.color('📋 Template →', 'yellow')} ${this.color(to, 'dim')} ${this.color(`[${template.name}]`, 'bold')}\n${vars}\n`,
    )
    return { providerMessageId: id, status: 'sent' }
  }

  async uploadMedia(_file: Blob, _mimeType: string): Promise<string> {
    return `console-media-${Date.now()}`
  }

  async downloadMedia(_mediaId: string): Promise<Blob> {
    return new Blob([], { type: 'application/octet-stream' })
  }

  async markRead(_providerMessageId: string): Promise<void> {
    // no-op
  }

  async showTypingFor(_providerMessageId: string): Promise<void> {
    this.write(this.color('   ✏️  digitando…', 'dim'))
  }

  async setTyping(_to: string, state: 'typing' | 'recording' | 'idle'): Promise<void> {
    if (state !== 'idle') {
      this.write(this.color(`   ${state === 'recording' ? '🎙️ gravando…' : '✏️ digitando…'}`, 'dim'))
    }
  }

  async react(to: string, providerMessageId: string, emoji: string): Promise<SendResult> {
    const id = this.newId()
    this.write(
      `\n${this.color('🟢 Reaction →', 'cyan')} ${this.color(to, 'dim')} ${emoji || '(remove)'} on ${this.color(providerMessageId, 'dim')}\n`,
    )
    return { providerMessageId: id, status: 'sent' }
  }

  /**
   * Helper para o CLI: cria um inbound a partir de texto puro.
   */
  buildTextInbound(from: string, text: string): NormalizedInbound[] {
    return [
      {
        providerMessageId: `console_in_${Date.now()}_${++counter}`,
        from,
        type: 'text',
        text,
        timestamp: new Date(),
        raw: { source: 'console', text },
      },
    ]
  }

  parseInbound(payload: unknown): NormalizedInbound[] {
    // Console aceita payload já normalizado pra simplicidade
    if (
      payload &&
      typeof payload === 'object' &&
      'from' in payload &&
      'text' in payload &&
      typeof (payload as { text: unknown }).text === 'string'
    ) {
      const p = payload as { from: string; text: string }
      return this.buildTextInbound(p.from, p.text)
    }
    return []
  }

  verifyWebhook(_headers: Record<string, string>, _rawBody: string): boolean {
    return true
  }

  async getQualityStatus(): Promise<QualityStatus> {
    return { rating: 'GREEN', tier: 'unlimited' }
  }
}
