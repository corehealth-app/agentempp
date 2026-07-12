import type { ServiceClient } from '@mpp/db'
import type { MealType } from './personal-meal-windows.js'

interface GapSnapshot {
  day_status?: string | null
  gap_reminder_sent_at?: string | null
}

interface GapMessage {
  raw_payload?: unknown
}

const VALID_MEAL_TYPES = new Set<MealType>(['cafe', 'almoco', 'lanche', 'jantar', 'ceia'])

export function resolveActiveGapReminderMealTypes(
  snapshot: GapSnapshot | null,
  messages: GapMessage[],
  referenceTimestamp: Date,
): MealType[] {
  if (snapshot?.day_status !== 'pending_close' || !snapshot.gap_reminder_sent_at) return []
  const reminderAt = new Date(snapshot.gap_reminder_sent_at)
  if (!Number.isFinite(reminderAt.getTime()) || reminderAt > referenceTimestamp) return []

  for (const message of messages) {
    const payload = message.raw_payload
    if (!payload || typeof payload !== 'object') continue
    const raw = payload as { source?: unknown; gap?: unknown }
    if (raw.source !== 'daily_gap_checker' || !Array.isArray(raw.gap)) continue
    return Array.from(
      new Set(
        raw.gap.filter(
          (value): value is MealType =>
            typeof value === 'string' && VALID_MEAL_TYPES.has(value as MealType),
        ),
      ),
    )
  }
  return []
}

export async function loadActiveGapReminderMealTypes(
  supabase: ServiceClient,
  userId: string,
  localDate: string,
  referenceTimestamp: Date,
): Promise<{ mealTypes: MealType[] }> {
  const { data: snapshot, error: snapshotError } = await supabase
    .from('daily_snapshots')
    .select('day_status, gap_reminder_sent_at')
    .eq('user_id', userId)
    .eq('date', localDate)
    .maybeSingle()
  if (snapshotError) {
    throw new Error(snapshotError.message ?? 'active gap reminder snapshot lookup failed')
  }

  const typedSnapshot = snapshot as GapSnapshot | null
  if (
    typedSnapshot?.day_status !== 'pending_close' ||
    !typedSnapshot.gap_reminder_sent_at ||
    new Date(typedSnapshot.gap_reminder_sent_at) > referenceTimestamp
  ) {
    return { mealTypes: [] }
  }

  // biome-ignore lint/suspicious/noExplicitAny: raw_payload ainda nao consta nos tipos gerados
  const { data: messages, error: messagesError } = await (supabase as any)
    .from('messages')
    .select('raw_payload, created_at')
    .eq('user_id', userId)
    .eq('direction', 'out')
    .eq('raw_payload->>source', 'daily_gap_checker')
    .gte('created_at', typedSnapshot.gap_reminder_sent_at)
    .order('created_at', { ascending: false })
    .limit(3)
  if (messagesError) {
    throw new Error(messagesError.message ?? 'active gap reminder message lookup failed')
  }

  return {
    mealTypes: resolveActiveGapReminderMealTypes(
      typedSnapshot,
      (messages ?? []) as GapMessage[],
      referenceTimestamp,
    ),
  }
}
