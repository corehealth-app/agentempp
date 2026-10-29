// Next static analysis must see the bounded recovery timeout in this wrapper.
export const maxDuration = 45

export {
  dynamic,
  GET,
  HEAD,
  POST,
  runtime,
} from '@/app/api/mobile/v1/auth/password-recovery/route'
