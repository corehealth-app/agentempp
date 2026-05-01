/**
 * Groq Whisper-large-v3-turbo — STT extremamente barato (~$0.04/h).
 */
import OpenAI from 'openai'

export interface STTConfig {
  apiKey: string
  baseURL?: string
}

export interface TranscribeParams {
  audio: Blob | Buffer | Uint8Array
  filename?: string
  language?: string // ISO-639-1, default 'pt'
  prompt?: string // contexto opcional pra melhorar acurácia
  temperature?: number
}

export interface TranscribeResult {
  text: string
  language?: string
  duration?: number
  latencyMs: number
}

export class GroqSTT {
  private client: OpenAI

  constructor(cfg: STTConfig) {
    this.client = new OpenAI({
      apiKey: cfg.apiKey,
      baseURL: cfg.baseURL ?? 'https://api.groq.com/openai/v1',
    })
  }

  async transcribe(p: TranscribeParams): Promise<TranscribeResult> {
    const start = Date.now()

    const file =
      p.audio instanceof Blob
        ? new File([p.audio], p.filename ?? 'audio.ogg', { type: p.audio.type || 'audio/ogg' })
        : new File([p.audio], p.filename ?? 'audio.ogg', { type: 'audio/ogg' })

    const result = await this.client.audio.transcriptions.create({
      file,
      model: 'whisper-large-v3-turbo',
      language: p.language ?? 'pt',
      prompt: p.prompt,
      temperature: p.temperature ?? 0,
      response_format: 'verbose_json',
    })

    return {
      text: result.text,
      language: (result as unknown as { language?: string }).language,
      duration: (result as unknown as { duration?: number }).duration,
      latencyMs: Date.now() - start,
    }
  }
}
