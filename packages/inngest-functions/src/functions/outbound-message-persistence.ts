import type { ServiceClient } from '@mpp/db'
import type { buildOutboundMessageRows } from './outbound-message-rows.js'

type OutboundMessageRow = ReturnType<typeof buildOutboundMessageRows>[number] & {
  media_url?: string | null
}

/** Persists one provider delivery idempotently and returns messages.id. */
export async function persistOutboundMessage(
  supabase: ServiceClient,
  row: OutboundMessageRow,
): Promise<string> {
  if (row.provider_message_id) {
    const { data: existing } = await supabase
      .from('messages')
      .select('id')
      .eq('provider', row.provider)
      .eq('provider_message_id', row.provider_message_id)
      .maybeSingle()
    const existingId = (existing as { id?: string } | null)?.id
    if (existingId) return existingId
  }

  const { data: inserted, error: insertError } = await supabase
    .from('messages')
    .insert(row)
    .select('id')
    .single()
  if (!insertError && inserted) return (inserted as { id: string }).id

  if (row.provider_message_id) {
    const { data: raced } = await supabase
      .from('messages')
      .select('id')
      .eq('provider', row.provider)
      .eq('provider_message_id', row.provider_message_id)
      .maybeSingle()
    const racedId = (raced as { id?: string } | null)?.id
    if (racedId) return racedId
  }
  throw new Error(insertError?.message ?? 'outbound message persistence failed')
}
