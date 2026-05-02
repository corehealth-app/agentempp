'use client'

/**
 * Listener Realtime que dispara router.refresh() quando uma nova msg
 * IN/OUT é inserida. Ler do Supabase Realtime canal `messages`.
 *
 * Como /messages é Server Component, refresh() rebusca os dados do
 * server e atualiza a UI sem reload de página.
 */
import { useRouter } from 'next/navigation'
import { useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

export function MessagesRealtimeListener() {
  const router = useRouter()

  useEffect(() => {
    const supabase = createClient()
    const channel = supabase
      .channel('admin:messages-stream')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'messages' },
        () => {
          // Debounce simples: usa nextTick pra agrupar burst de msgs
          if (timer) clearTimeout(timer)
          timer = setTimeout(() => router.refresh(), 250)
        },
      )
      .subscribe()

    let timer: ReturnType<typeof setTimeout> | null = null
    return () => {
      if (timer) clearTimeout(timer)
      supabase.removeChannel(channel)
    }
  }, [router])

  return null
}
