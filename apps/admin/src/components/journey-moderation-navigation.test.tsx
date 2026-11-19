import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'

vi.mock('next/navigation', () => ({ usePathname: () => '/journey-moderation' }))
vi.mock('@/lib/supabase/client', () => ({ createClient: () => ({ auth: {} }) }))

import { Sidebar } from './sidebar'

describe('actual operational navigation rendering', () => {
  it.each([
    ['support', false],
    ['content_editor', false],
    ['nutrition_admin', false],
    ['operations_admin', true],
    ['master_admin', true],
  ] as const)('shows the guarded moderation entry only for %s', (role, visible) => {
    const html = renderToStaticMarkup(<Sidebar role={role} userEmail="synthetic@example.invalid" />)
    expect(html.includes('href="/journey-moderation"')).toBe(visible)
    if (role !== 'content_editor') expect(html).toContain('href="/users"')
  })
})
