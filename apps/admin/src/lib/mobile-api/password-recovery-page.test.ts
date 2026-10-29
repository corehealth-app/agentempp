import { runInNewContext } from 'node:vm'
import { expect, it, vi } from 'vitest'
import { passwordRecoveryPage } from './password-recovery-page'

const proof = 'pkce_synthetic-proof-not-a-real-credential'
const newPassword = 'Synthetic password 731!'

function page(
  reply = { status: 'password_changed' },
  httpOK = true,
  language = 'pt-BR',
  options: { fragment?: string; enabled?: boolean } = {},
) {
  type Element = {
    value: string
    textContent: string
    hidden: boolean
    disabled: boolean
    focus: ReturnType<typeof vi.fn>
    setAttribute: ReturnType<typeof vi.fn>
    removeAttribute: ReturnType<typeof vi.fn>
    addEventListener: (
      name: string,
      listener: (event: { preventDefault: () => void }) => Promise<void>,
    ) => void
  }
  let submit: ((event: { preventDefault: () => void }) => Promise<void>) | undefined
  const elements = Object.fromEntries(
    ['form', 'status', 'submit', 'password', 'confirmation', 'h1'].map((id) => [
      id,
      {
        value: '',
        textContent: '',
        hidden: false,
        disabled: false,
        focus: vi.fn(),
        setAttribute: vi.fn(),
        removeAttribute: vi.fn(),
        addEventListener: (_name: string, listener: typeof submit) => {
          submit = listener
        },
      },
    ]),
  ) as Record<string, Element>
  const fetcher = vi.fn(async (_url: string, _init: RequestInit) => ({
    ok: httpOK,
    json: async () => reply,
  }))
  const history = { replaceState: vi.fn() }
  let expire: (() => void) | undefined
  const deadline = vi.fn((callback: () => void, _milliseconds: number) => {
    expire = callback
    return 1
  })
  const clearDeadline = vi.fn()
  const html = passwordRecoveryPage('synthetic-nonce', language, options.enabled ?? true)
  const script = html.match(/<script nonce="synthetic-nonce">([\s\S]*?)<\/script>/)?.[1]
  if (!script) throw new Error('page script missing')
  runInNewContext(script, {
    URLSearchParams,
    AbortController,
    setTimeout: deadline,
    clearTimeout: clearDeadline,
    history,
    fetch: fetcher,
    location: {
      hash: options.fragment ?? `#token_hash=${proof}&type=recovery`,
      pathname: '/api/mobile/v1/auth/password-recovery',
    },
    document: { getElementById: (id: string) => elements[id], querySelector: () => elements.h1 },
  })
  return {
    elements,
    fetcher,
    history,
    deadline,
    clearDeadline,
    expireRequest: () => {
      if (!expire) throw new Error('request deadline was not registered')
      expire()
    },
    submit: () => {
      if (!submit) throw new Error('submit handler missing')
      return submit({ preventDefault: vi.fn() })
    },
  }
}

it.each([
  '',
  '#type=recovery',
  `#token_hash=${proof}&type=signup`,
  '#token_hash=short&type=recovery',
])('hides invalid recovery input without contacting Auth: %s', (fragment) => {
  const p = page(undefined, undefined, undefined, { fragment })
  expect(p.elements.form.hidden).toBe(true)
  expect(p.elements.status.textContent).toContain('inválido ou expirou')
  expect(p.fetcher).not.toHaveBeenCalled()
  expect(p.history.replaceState).toHaveBeenCalledWith(
    null,
    '',
    '/api/mobile/v1/auth/password-recovery',
  )
})

it('keeps the disabled feature unavailable even with a structurally valid hash', () => {
  const p = page(undefined, undefined, undefined, { enabled: false })
  expect(p.elements.form.hidden).toBe(true)
  expect(p.elements.status.textContent).toContain('temporariamente indisponível')
  expect(p.fetcher).not.toHaveBeenCalled()
})

it('clears sensitive fields and reports an uncertain network outcome without retry', async () => {
  const p = page()
  p.fetcher.mockRejectedValueOnce(new Error('synthetic connection failure'))
  p.elements.password.value = newPassword
  p.elements.confirmation.value = newPassword
  await p.submit()
  await p.submit()
  expect(p.fetcher).toHaveBeenCalledOnce()
  expect(p.elements.password.value).toBe('')
  expect(p.elements.confirmation.value).toBe('')
  expect(p.elements.form.hidden).toBe(true)
  expect(p.elements.status.textContent).toContain('Não foi possível confirmar')
})

it('bounds a stalled request and clears the form without retrying or claiming success', async () => {
  const p = page()
  p.fetcher.mockImplementationOnce(
    (_url, init) =>
      new Promise((_resolve, reject) => {
        init.signal?.addEventListener('abort', () => reject(new Error('synthetic deadline')))
      }),
  )
  p.elements.password.value = newPassword
  p.elements.confirmation.value = newPassword
  const pending = p.submit()
  expect(p.elements.submit.disabled).toBe(true)
  expect(p.deadline).toHaveBeenCalledWith(expect.any(Function), 60_000)
  p.expireRequest()
  await pending
  await p.submit()
  expect(p.fetcher).toHaveBeenCalledOnce()
  expect(p.clearDeadline).toHaveBeenCalledWith(1)
  expect(p.elements.password.value).toBe('')
  expect(p.elements.confirmation.value).toBe('')
  expect(p.elements.form.hidden).toBe(true)
  expect(p.elements.status.textContent).toContain('Não foi possível confirmar')
  expect(p.elements.status.textContent).not.toContain('Senha alterada')
})

it('loads without consuming the proof, validates locally, submits once and clears sensitive fields', async () => {
  const p = page()
  expect(p.fetcher).not.toHaveBeenCalled()
  expect(p.history.replaceState).toHaveBeenCalledWith(
    null,
    '',
    '/api/mobile/v1/auth/password-recovery',
  )
  p.elements.password.value = newPassword
  p.elements.confirmation.value = 'different'
  await p.submit()
  expect(p.fetcher).not.toHaveBeenCalled()
  expect(p.elements.confirmation.focus).toHaveBeenCalledOnce()
  p.elements.confirmation.value = newPassword
  const first = p.submit()
  await p.submit()
  await first
  expect(p.fetcher).toHaveBeenCalledOnce()
  const call = p.fetcher.mock.calls[0]
  if (!call) throw new Error('expected one request')
  const [, init] = call
  expect(JSON.parse(String(init.body))).toEqual({
    token_hash: proof,
    password: newPassword,
    password_confirmation: newPassword,
  })
  expect(init.credentials).toBe('omit')
  expect(p.elements.password.value).toBe('')
  expect(p.elements.confirmation.value).toBe('')
  expect(p.elements.form.hidden).toBe(true)
  expect(p.elements.h1.focus).toHaveBeenCalledOnce()
  expect(p.elements.status.textContent).toBe(
    'Senha alterada. Abra o Performe AI e entre com sua nova senha.',
  )
})

it.each([
  ['new_link_required', 'Este link é inválido ou expirou.'],
  ['password_rejected', 'A nova senha foi recusada.'],
  ['recovery_unavailable', 'O serviço de recuperação está indisponível.'],
  ['recovery_unconfirmed', 'Não foi possível confirmar a alteração.'],
])('shows the distinct %s result without retry', async (status, copy) => {
  const p = page({ status }, false)
  p.elements.password.value = newPassword
  p.elements.confirmation.value = newPassword
  await p.submit()
  expect(p.elements.status.textContent).toContain(copy)
  await p.submit()
  expect(p.fetcher).toHaveBeenCalledOnce()
})

it('confirms the result in English', async () => {
  const p = page({ status: 'password_changed' }, true, 'en-US')
  p.elements.password.value = newPassword
  p.elements.confirmation.value = newPassword
  await p.submit()
  expect(p.elements.status.textContent).toBe(
    'Password changed. Open Performe AI and sign in with your new password.',
  )
})
