import { ConsoleProvider } from './console.js'
import type { MessagingProvider } from './types.js'
import { WhatsAppCloudProvider } from './whatsapp-cloud.js'

export interface MessagingFactoryEnv {
  MESSAGING_PROVIDER?: string
  META_PHONE_NUMBER_ID?: string
  META_ACCESS_TOKEN?: string
  META_APP_SECRET?: string
  META_VERIFY_TOKEN?: string
}

export function createMessagingProvider(env: MessagingFactoryEnv = {}): MessagingProvider {
  const provider = env.MESSAGING_PROVIDER ?? 'console'
  switch (provider) {
    case 'console':
      return new ConsoleProvider()
    case 'whatsapp_cloud':
      if (
        !env.META_PHONE_NUMBER_ID ||
        !env.META_ACCESS_TOKEN ||
        !env.META_APP_SECRET ||
        !env.META_VERIFY_TOKEN
      ) {
        throw new Error(
          'whatsapp_cloud requer META_PHONE_NUMBER_ID, META_ACCESS_TOKEN, META_APP_SECRET, META_VERIFY_TOKEN',
        )
      }
      return new WhatsAppCloudProvider({
        phoneNumberId: env.META_PHONE_NUMBER_ID,
        accessToken: env.META_ACCESS_TOKEN,
        appSecret: env.META_APP_SECRET,
        verifyToken: env.META_VERIFY_TOKEN,
      })
    default:
      throw new Error(`Unknown MESSAGING_PROVIDER: ${provider}`)
  }
}
