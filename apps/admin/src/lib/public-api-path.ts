export function isSelfAuthenticatedApiPath(path: string): boolean {
  return (
    path.startsWith('/api/inngest') ||
    path.startsWith('/api/admin/send-message') ||
    path.startsWith('/api/mobile/') ||
    path === '/api/webhooks/revenuecat' ||
    path === '/api/internal/conversation-media/process-v2' ||
    path === '/api/internal/flow-meal-gap'
  )
}
