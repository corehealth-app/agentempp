import { describe, expect, test } from 'vitest'
import { GET as sourceGet, POST as sourcePost } from '@/app/api/mobile/v1/flow/chat/route'
import {
  GET as dedicatedGet,
  POST as dedicatedPost,
  maxDuration,
  runtime,
} from './app/api/mobile/v1/flow/chat/route'

describe('dedicated Flow chat entrypoint', () => {
  test('publishes the authoritative authenticated handlers with static runtime limits', () => {
    expect(dedicatedGet).toBe(sourceGet)
    expect(dedicatedPost).toBe(sourcePost)
    expect(runtime).toBe('nodejs')
    expect(maxDuration).toBe(300)
  })
})
