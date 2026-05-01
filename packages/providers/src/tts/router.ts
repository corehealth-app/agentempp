/**
 * Router de TTS: decide ElevenLabs (âncoras) vs Cartesia (operacional)
 * baseado em hint do agente.
 */
import type { CartesiaConfig } from './cartesia.js'
import { CartesiaTTS } from './cartesia.js'
import type { ElevenLabsConfig } from './elevenlabs.js'
import { ElevenLabsTTS } from './elevenlabs.js'

export type TTSAnchorType =
  | 'welcome'
  | 'daily_closing'
  | 'reevaluation'
  | 'block_completed'
  | 'badge_earned'
  | 'standard'

export const ANCHOR_TYPES: TTSAnchorType[] = [
  'welcome',
  'daily_closing',
  'reevaluation',
  'block_completed',
  'badge_earned',
]

export interface TTSRouterConfig {
  elevenlabs?: ElevenLabsConfig
  cartesia?: CartesiaConfig
}

export class TTSRouter {
  private elevenlabs?: ElevenLabsTTS
  private cartesia?: CartesiaTTS

  constructor(cfg: TTSRouterConfig) {
    if (cfg.elevenlabs) this.elevenlabs = new ElevenLabsTTS(cfg.elevenlabs)
    if (cfg.cartesia) this.cartesia = new CartesiaTTS(cfg.cartesia)
  }

  async synthesize(text: string, anchorType: TTSAnchorType = 'standard') {
    const useAnchor = ANCHOR_TYPES.includes(anchorType)
    if (useAnchor && this.elevenlabs) {
      return { result: await this.elevenlabs.synthesize(text), provider: 'elevenlabs' as const }
    }
    if (this.cartesia) {
      return { result: await this.cartesia.synthesize(text), provider: 'cartesia' as const }
    }
    if (this.elevenlabs) {
      return { result: await this.elevenlabs.synthesize(text), provider: 'elevenlabs' as const }
    }
    throw new Error('Nenhum provider TTS configurado')
  }
}
