/**
 * Valida a view v_active_prompts inspecionando o system prompt montado
 * para cada stage. Compara contagem de regras esperadas vs incluídas.
 *
 * Uso:
 *   pnpm --filter @mpp/scripts validate:prompts
 */
import { createClient } from '@supabase/supabase-js'
import type { Database } from '@mpp/db'

function env(key: string): string {
  const v = process.env[key]
  if (!v) throw new Error(`Missing env var: ${key}`)
  return v
}

interface StageExpectation {
  stage: string
  ruleTipos: string[]
  expectedCount: number // regras_gerais + tipo do stage
}

const EXPECTATIONS: StageExpectation[] = [
  { stage: 'coleta_dados', ruleTipos: ['regras_gerais', 'coleta_dados'], expectedCount: 21 + 13 },
  { stage: 'recomposicao', ruleTipos: ['regras_gerais', 'recomposicao'], expectedCount: 21 + 23 },
  { stage: 'ganho_massa', ruleTipos: ['regras_gerais', 'ganho_massa'], expectedCount: 21 + 19 },
  { stage: 'manutencao', ruleTipos: ['regras_gerais', 'manutencao'], expectedCount: 21 + 12 },
  // analista_diario e engajamento usam apenas regras_gerais (não há tipo específico)
  { stage: 'analista_diario', ruleTipos: ['regras_gerais'], expectedCount: 21 },
  { stage: 'engajamento', ruleTipos: ['regras_gerais'], expectedCount: 21 },
]

async function main() {
  const supabase = createClient<Database>(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  console.log('━━━ Validação v_active_prompts ━━━\n')

  // Pega prompts da view
  const { data: prompts, error } = await supabase.from('v_active_prompts').select('*')
  if (error) throw error
  if (!prompts) throw new Error('Sem prompts retornados')

  console.log(`📋 ${prompts.length} stages encontrados na view`)
  console.log('')

  let allOk = true

  for (const expected of EXPECTATIONS) {
    const row = prompts.find((p) => p.stage === expected.stage)
    if (!row) {
      console.log(`❌ ${expected.stage.padEnd(20)} stage AUSENTE na view`)
      allOk = false
      continue
    }

    const prompt = row.system_prompt ?? ''
    const sectionCount = (prompt.match(/\n---\n/g) ?? []).length + 1
    const charCount = prompt.length
    const tokenEstimate = Math.ceil(charCount / 4)

    const status =
      sectionCount === expected.expectedCount
        ? '✅'
        : sectionCount > 0
          ? '⚠'
          : '❌'

    console.log(
      `${status} ${expected.stage.padEnd(20)} regras=${sectionCount.toString().padStart(3)} (esperado ${expected.expectedCount.toString().padStart(3)})  chars=${charCount.toString().padStart(6)}  ~tokens=${tokenEstimate}`,
    )
    console.log(`     model=${row.model}  T=${row.temperature}  maxTok=${row.max_tokens}`)

    if (sectionCount !== expected.expectedCount) {
      allOk = false
    }
  }

  console.log('')

  // Sample do primeiro prompt para inspeção visual
  const sample = prompts.find((p) => p.stage === 'recomposicao')
  if (sample?.system_prompt) {
    const preview = sample.system_prompt.slice(0, 500)
    console.log('📄 Sample (primeiros 500 chars de "recomposicao"):')
    console.log('─'.repeat(70))
    console.log(preview)
    console.log('─'.repeat(70))
  }

  // Custo estimado por chamada (Grok 4.1 Fast: $0.20/M input)
  console.log('\n💰 Custo estimado por chamada de LLM (apenas system prompt):')
  for (const row of prompts) {
    const tokens = Math.ceil((row.system_prompt?.length ?? 0) / 4)
    const costUsd = (tokens / 1_000_000) * 0.2 // Grok input
    console.log(`   ${row.stage?.padEnd(20)} ${tokens.toString().padStart(6)} tokens  $${costUsd.toFixed(5)}`)
  }

  if (!allOk) {
    console.log('\n💥 Validação FALHOU')
    process.exit(1)
  }
  console.log('\n✅ Todas as expectativas atendidas.')
}

main().catch((err) => {
  console.error('💥 Falha:', err)
  process.exit(1)
})
