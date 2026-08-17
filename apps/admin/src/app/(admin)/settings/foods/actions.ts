'use server'

import { revalidatePath } from 'next/cache'
import { createServiceClient } from '@/lib/supabase/server'

export interface FoodInput {
  id?: number
  name_pt: string
  category: string | null
  kcal_per_100g: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
  country_code: string
  source: string | null
}

type FoodWrite = Omit<FoodInput, 'source'> & {
  source: 'admin_unverified'
  is_verified: false
  source_ref: null
}

function unverifiedAdminWrite(input: FoodInput): FoodWrite {
  return {
    ...input,
    source: 'admin_unverified',
    is_verified: false,
    source_ref: null,
  }
}

export async function upsertFood(input: FoodInput) {
  const write = unverifiedAdminWrite(input)
  const svc = createServiceClient()

  if (write.id) {
    const { data: existing, error: lookupError } = await svc
      .from('food_db')
      .select('is_verified')
      .eq('id', write.id)
      .maybeSingle()
    if (lookupError) return { ok: false, error: lookupError.message }
    if (!existing) return { ok: false, error: 'Alimento não encontrado.' }
    if (existing.is_verified) {
      return {
        ok: false,
        error: 'Referências verificadas são imutáveis. Adicione uma nova referência em quarentena.',
      }
    }
    const { id, ...rest } = write
    const { data: updated, error } = await svc
      .from('food_db')
      .update(rest)
      .eq('id', id)
      .eq('is_verified', false)
      .select('id')
      .maybeSingle()
    if (error) return { ok: false, error: error.message }
    if (!updated) return { ok: false, error: 'A referência mudou e não pode mais ser editada.' }
  } else {
    const { error } = await svc.from('food_db').insert(write)
    if (error) return { ok: false, error: error.message }
  }

  revalidatePath('/settings/foods')
  return { ok: true }
}

export async function deleteFood(id: number) {
  const svc = createServiceClient()
  const { data: existing, error: lookupError } = await svc
    .from('food_db')
    .select('is_verified')
    .eq('id', id)
    .maybeSingle()
  if (lookupError) return { ok: false, error: lookupError.message }
  if (!existing) return { ok: false, error: 'Alimento não encontrado.' }
  if (existing.is_verified) {
    return { ok: false, error: 'Referências verificadas não podem ser excluídas pelo painel.' }
  }
  const { data: deleted, error } = await svc
    .from('food_db')
    .delete()
    .eq('id', id)
    .eq('is_verified', false)
    .select('id')
    .maybeSingle()
  if (error) return { ok: false, error: error.message }
  if (!deleted) return { ok: false, error: 'A referência mudou e não pode mais ser excluída.' }
  revalidatePath('/settings/foods')
  return { ok: true }
}
