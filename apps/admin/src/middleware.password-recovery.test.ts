import { createServerClient } from '@supabase/ssr'
import { NextRequest } from 'next/server'
import { beforeEach, expect, it, vi } from 'vitest'
import { middleware } from './middleware'

const { getUser, serverClient } = vi.hoisted(() => {
  const getUser = vi.fn(async () => ({ data: { user: null } }))
  return { getUser, serverClient: vi.fn(() => ({ auth: { getUser } })) }
})
vi.mock('@supabase/ssr', () => ({ createServerClient: serverClient }))
beforeEach(() => {
  vi.clearAllMocks()
})

it('does not restore or refresh an administrative session for the exact recovery route', async () => {
  const response = await middleware(
    new NextRequest(
      'https://performe-ai-staging-bff.vercel.app/api/mobile/v1/auth/password-recovery',
      { headers: { cookie: 'admin-session=synthetic' } },
    ),
  )
  expect(response.status).toBe(200)
  expect(createServerClient).not.toHaveBeenCalled()
  expect(getUser).not.toHaveBeenCalled()
  expect(response.headers.has('set-cookie')).toBe(false)
})

it('keeps the administrative login guard intact', async () => {
  const response = await middleware(new NextRequest('https://panel.example/dashboard'))
  expect(createServerClient).toHaveBeenCalledTimes(1)
  expect(getUser).toHaveBeenCalledTimes(1)
  expect(response.headers.get('location')).toBe('https://panel.example/login')
})

it('does not broaden the bypass to nested paths', async () => {
  await middleware(
    new NextRequest('https://panel.example/api/mobile/v1/auth/password-recovery/extra'),
  )
  expect(createServerClient).toHaveBeenCalledTimes(1)
})
