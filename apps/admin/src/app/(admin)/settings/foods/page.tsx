import { PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { FoodsTable } from './table'

export const dynamic = 'force-dynamic'

interface SearchParams {
  q?: string
  category?: string
  country?: string
  source?: string
}

export default async function FoodsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>
}) {
  const params = await searchParams
  const svc = createServiceClient()

  let query = (svc as unknown as {
    from: (t: string) => {
      select: (s: string, opts?: { count?: 'exact' }) => {
        order: (col: string, opt: { ascending: boolean }) => {
          limit: (n: number) => Promise<{
            data: Array<Record<string, unknown>> | null
            count: number | null
          }>
        }
      }
    }
  })
    .from('food_db')
    .select(
      'id, name_pt, category, kcal_per_100g, protein_g, carbs_g, fat_g, fiber_g, country_code, source',
      { count: 'exact' },
    )

  // PostgREST chained filters (cast for typing)
  let q = query as unknown as {
    ilike: (col: string, pat: string) => typeof q
    eq: (col: string, val: string) => typeof q
    order: (col: string, opt: { ascending: boolean }) => typeof q
    limit: (n: number) => Promise<{
      data: Array<Record<string, unknown>> | null
      count: number | null
    }>
  }

  if (params.q) q = q.ilike('name_pt', `%${params.q}%`)
  if (params.category) q = q.eq('category', params.category)
  if (params.country) q = q.eq('country_code', params.country)
  if (params.source) q = q.eq('source', params.source)

  const { data, count } = await q.order('name_pt', { ascending: true }).limit(500)

  // Distinct categories pra filter
  const { data: catRows } = await (svc as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        order: (col: string, opt: { ascending: boolean }) => Promise<{
          data: Array<{ category: string | null }> | null
        }>
      }
    }
  })
    .from('food_db')
    .select('category')
    .order('category', { ascending: true })

  const categories = Array.from(
    new Set((catRows ?? []).map((r) => r.category).filter((c): c is string => !!c)),
  ).sort()

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Configuração' }, { label: 'Banco de alimentos' }]}
        title="Banco de alimentos"
        description={
          <>
            Base nutricional usada pelo agente quando registra refeições. Vision identifica os
            itens, esta base fornece kcal/proteína/carb/gordura por 100g. {count ?? 0} alimentos
            cadastrados (BR + alias). Adicione novos quando o agente devolver "0 kcal sem match".
          </>
        }
      />

      <FoodsTable
        rows={(data ?? []) as FoodRow[]}
        categories={categories}
        searchParams={params}
      />
    </div>
  )
}

export type FoodRow = {
  id: number
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
