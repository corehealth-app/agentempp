/**
 * One-shot: cria produtos+preços Stripe via SDK usando o helper
 * setupStripeProducts() já validado em /api/stripe/setup-products.
 * Roda standalone com o service_role do Supabase (mesmo padrão do worker).
 *
 * Uso:
 *   tsx apps/admin/scripts/stripe-setup.ts
 */
import { setupStripeProducts } from '../src/lib/stripe'

async function main() {
  console.log('Sincronizando catálogo no Stripe...')
  const results = await setupStripeProducts()
  for (const r of results) {
    console.log(
      `  ${r.created ? '✓ CRIADO ' : '· EXISTIA'} ${r.lookup_key} → ${r.price_id}`,
    )
  }
  console.log(`\nTotal: ${results.length} produto(s)`)
}

main().catch((e) => {
  console.error('FALHA:', e instanceof Error ? e.message : e)
  process.exit(1)
})
