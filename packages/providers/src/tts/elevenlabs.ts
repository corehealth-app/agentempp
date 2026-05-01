/**
 * ElevenLabs TTS — voz custom (Dr. Roberto).
 * Usado para mensagens-âncora (boas-vindas, fechamento, conquistas).
 */

export interface ElevenLabsConfig {
  apiKey: string
  voiceId: string
  modelId?: string // default 'eleven_multilingual_v2'
  outputFormat?: string // default 'mp3_44100_128'
}

export interface TTSResult {
  audio: Uint8Array
  mimeType: string
  durationMs: number
  costUsd?: number
}

export class ElevenLabsTTS {
  constructor(private cfg: ElevenLabsConfig) {}

  async synthesize(text: string): Promise<TTSResult> {
    const start = Date.now()
    const url = `https://api.elevenlabs.io/v1/text-to-speech/${this.cfg.voiceId}?output_format=${this.cfg.outputFormat ?? 'mp3_44100_128'}`

    const r = await fetch(url, {
      method: 'POST',
      headers: {
        'xi-api-key': this.cfg.apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        text,
        model_id: this.cfg.modelId ?? 'eleven_multilingual_v2',
        voice_settings: {
          stability: 0.5,
          similarity_boost: 1.0,
          style: 1.0,
          use_speaker_boost: false,
          speed: 1.0,
        },
      }),
    })
    if (!r.ok) {
      const body = await r.text()
      throw new Error(`ElevenLabs error ${r.status}: ${body}`)
    }
    const audio = new Uint8Array(await r.arrayBuffer())
    return {
      audio,
      mimeType: 'audio/mpeg',
      durationMs: Date.now() - start,
    }
  }
}
