export function isSelfAuthenticatedApiPath(path: string): boolean {
  return (
    path.startsWith('/api/inngest') ||
    path.startsWith('/api/admin/send-message') ||
    path.startsWith('/api/mobile/')
  )
}
