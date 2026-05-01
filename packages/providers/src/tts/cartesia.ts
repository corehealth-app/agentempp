/**
 * Cartesia Sonic TTS — voz padrão para mensagens operacionais.
 * 6× mais barato que ElevenLabs com qualidade muito boa em PT-BR.
 */

export interface CartesiaConfig {
  apiKey: string
  voiceId: string
  modelId?: string // default 'sonic-2'
  language?: string // default 'pt'
}

import type { TTSResult } from './elevenlabs.js'

export class CartesiaTTS {
  constructor(private cfg: CartesiaConfig) {}

  async synthesize(text: string): Promise<TTSResult> {
    const start = Date.now()
    const r = await fetch('https://api.cartesia.ai/tts/bytes', {
      method: 'POST',
      headers: {
        'X-API-Key': this.cfg.apiKey,
        'Cartesia-Version': '2024-06-10',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model_id: this.cfg.modelId ?? 'sonic-2',
        transcript: text,
        voice: { mode: 'id', id: this.cfg.voiceId },
        output_format: {
          container: 'mp3',
          encoding: 'mp3',
          sample_rate: 44100,
        },
        language: this.cfg.language ?? 'pt',
      }),
    })
    if (!r.ok) {
      const body = await r.text()
      throw new Error(`Cartesia error ${r.status}: ${body}`)
    }
    const audio = new Uint8Array(await r.arrayBuffer())
    return {
      audio,
      mimeType: 'audio/mpeg',
      durationMs: Date.now() - start,
    }
  }
}
