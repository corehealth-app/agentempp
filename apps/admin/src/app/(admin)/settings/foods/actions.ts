'use server'

import { createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

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

export async function upsertFood(input: FoodInput) {
  const svc = createServiceClient() as unknown as {
    from: (t: string) => {
      insert: (row: FoodInput) => Promise<{ error: { message: string } | null }>
      update: (row: Partial<FoodInput>) => {
        eq: (col: string, v: number) => Promise<{ error: { message: string } | null }>
      }
    }
  }

  if (input.id) {
    const { id, ...rest } = input
    const { error } = await svc.from('food_db').update(rest).eq('id', id)
    if (error) return { ok: false, error: error.message }
  } else {
    const { error } = await svc.from('food_db').insert(input)
    if (error) return { ok: false, error: error.message }
  }

  revalidatePath('/settings/foods')
  return { ok: true }
}

export async function deleteFood(id: number) {
  const svc = createServiceClient() as unknown as {
    from: (t: string) => {
      delete: () => {
        eq: (col: string, v: number) => Promise<{ error: { message: string } | null }>
      }
    }
  }
  const { error } = await svc.from('food_db').delete().eq('id', id)
  if (error) return { ok: false, error: error.message }
  revalidatePath('/settings/foods')
  return { ok: true }
}
