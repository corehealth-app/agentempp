'use client'

/**
 * Wrappers client-side pra componentes lazy. Permite usar `ssr: false`
 * em next/dynamic, que não é permitido direto em Server Components.
 *
 * Os 2 componentes aqui são pesados (websocket realtime, modal de busca)
 * mas não bloqueiam o conteúdo principal do /messages — então carregam
 * só após hidratação.
 */
import dynamic from 'next/dynamic'

export const LazyRealtimeListener = dynamic(
  () => import('./realtime-listener').then((m) => ({ default: m.MessagesRealtimeListener })),
  { ssr: false },
)

export const LazySearchTrigger = dynamic(
  () => import('./search-modal').then((m) => ({ default: m.SearchTrigger })),
  { ssr: false, loading: () => <div className="h-7 w-32" /> },
)
