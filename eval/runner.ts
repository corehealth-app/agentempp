/**
 * Eval suite runner — gate de CI antes de publicar mudanças em prompts.
 *
 * Uso:
 *   pnpm eval
 *
 * Para cada caso:
 *  1. cria/reseta usuário de teste
 *  2. chama processMessage com input
 *  3. verifica must_contain_any e should_call_tools
 *  4. (opcional) LLM-as-Judge para min_score
 *
 * Sai com exit code 1 se houver regressão.
 */
import { createClient } from '@supabase/supabase-js'
import { processMessage } from '@mpp/agent'
import type { Database } from '@mpp/db'
import { OpenRouterLLM } from '@mpp/providers'
import * as fs from 'node:fs'
import * as path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

interface Expectation {
  min_score?: number
  must_contain_any?: string[]
  must_contain_all?: string[]
  should_call_tools?: string[]
}

interface EvalCase {
  name: string
  stage?: string
  input: string
  expected: Expectation
}

function env(k: string): string {
  const v = process.env[k]
  if (!v) throw new Error(`Missing ${k}`)
  return v
}

async function main() {
  const supabase = createClient<Database>(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const llm = new OpenRouterLLM({ apiKey: env('OPENROUTER_API_KEY') })

  const casesDir = path.join(__dirname, 'cases')
  const allCases: Array<{ file: string; cases: EvalCase[] }> = []
  for (const file of fs.readdirSync(casesDir)) {
    if (!file.endsWith('.json')) continue
    const cases = JSON.parse(fs.readFileSync(path.join(casesDir, file), 'utf8')) as EvalCase[]
    allCases.push({ file, cases })
  }

  console.log(`━━━ Eval suite: ${allCases.flatMap((g) => g.cases).length} casos ━━━\n`)

  const failures: string[] = []
  const testUserWpp = '5500000000000'

  // Garante reset
  const { data: existing } = await supabase
    .from('users')
    .select('id')
    .eq('wpp', testUserWpp)
    .maybeSingle()
  if (existing) await supabase.from('users').delete().eq('id', existing.id)

  for (const group of allCases) {
    console.log(`\n📁 ${group.file}`)
    for (const c of group.cases) {
      try {
        const result = await processMessage(
          { supabase, llm },
          {
            from: testUserWpp,
            providerMessageId: `eval_${Date.now()}_${Math.random()}`,
            text: c.input,
            contentType: 'text',
            provider: 'eval_runner',
            timestamp: new Date(),
          },
        )

        const text = result.text.toLowerCase()
        const errors: string[] = []

        if (c.expected.must_contain_any) {
          const found = c.expected.must_contain_any.some((kw) => text.includes(kw.toLowerCase()))
          if (!found)
            errors.push(`não contém nenhum de: ${c.expected.must_contain_any.join(', ')}`)
        }
        if (c.expected.must_contain_all) {
          for (const kw of c.expected.must_contain_all) {
            if (!text.includes(kw.toLowerCase())) errors.push(`falta: ${kw}`)
          }
        }
        if (c.expected.should_call_tools) {
          const calledNames = result.toolCalls.map((t) => t.name)
          for (const tool of c.expected.should_call_tools) {
            if (!calledNames.includes(tool)) errors.push(`não chamou tool: ${tool}`)
          }
        }

        if (errors.length === 0) {
          console.log(`  ✅ ${c.name} (${result.latencyMs}ms, $${result.costUsd?.toFixed(5)})`)
        } else {
          console.log(`  ❌ ${c.name}`)
          for (const e of errors) console.log(`     ${e}`)
          failures.push(`${group.file}::${c.name}: ${errors.join('; ')}`)
        }
      } catch (e) {
        console.log(`  💥 ${c.name}: ${e instanceof Error ? e.message : e}`)
        failures.push(`${group.file}::${c.name}: ${e}`)
      }
    }
  }

  console.log(`\n━━━ ${failures.length} falhas ━━━`)
  if (failures.length) {
    for (const f of failures) console.log(`  - ${f}`)
    process.exit(1)
  }
  console.log('✅ Todos os casos passaram')
}

main().catch((e) => {
  console.error('💥', e)
  process.exit(1)
})
