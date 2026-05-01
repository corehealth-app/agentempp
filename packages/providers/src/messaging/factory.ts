import { ConsoleProvider } from './console.js'
import type { MessagingProvider } from './types.js'

export interface MessagingFactoryEnv {
  MESSAGING_PROVIDER?: string
  // futuros: META_*, TWILIO_*
}

export function createMessagingProvider(env: MessagingFactoryEnv = {}): MessagingProvider {
  const provider = env.MESSAGING_PROVIDER ?? 'console'
  switch (provider) {
    case 'console':
      return new ConsoleProvider()
    case 'whatsapp_cloud':
      throw new Error(
        'WhatsAppCloudProvider ainda não implementado — use MESSAGING_PROVIDER=console',
      )
    default:
      throw new Error(`Unknown MESSAGING_PROVIDER: ${provider}`)
  }
}
