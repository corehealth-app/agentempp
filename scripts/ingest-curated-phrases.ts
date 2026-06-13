/**
 * Ingest das frases curadas entregues pelo Roberto em 2026-06-13.
 *
 * Entrada:
 *   - scripts/data/curated-phrases-engagement.json (200 motivacionais)
 *   - scripts/data/curated-phrases-food.json (6 blocos prioritários, Fase A)
 *
 * Comportamento:
 *   - Idempotente: DELETE WHERE curated_by = CURATED_BY antes de inserir.
 *   - Food: expande cartesiano (alimento × frase) em food_education_phrases,
 *     food_canonical_name = alimento normalizado, tags = {bloco_id, polaridade}.
 *   - Engagement: inserção direta em engagement_phrases.
 *
 * Uso:
 *   set -a && . ./.env.local && set +a
 *   pnpm tsx scripts/ingest-curated-phrases.ts            # dry-run (conta sem inserir)
 *   pnpm tsx scripts/ingest-curated-phrases.ts --apply    # aplica em prod
 *
 * Autorização: Roberto entregou planilhas; Eduardo autorizou ingest em
 * 2026-06-13. Reversível via DELETE WHERE curated_by = CURATED_BY.
 */
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const CURATED_BY = 'roberto-2026-06-13'

interface FoodBlock {
  bloco_id: string
  polaridade: 'ruim' | 'bom'
  categoria_label: string
  alimentos: string[]
  frases: string[]
}

interface EngagementPhrase {
  phrase: string
  slot: string
}

interface FoodFile {
  _language: string
  _curated_by: string
  blocks: FoodBlock[]
}

interface EngagementFile {
  _language: string
  _curated_by: string
  phrases: EngagementPhrase[]
}

function normalize(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
}

async function execSql(sql: string, projectRef: string, token: string): Promise<unknown> {
  const res = await fetch(`https://api.supabase.com/v1/projects/${projectRef}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  })
  if (!res.ok) {
    throw new Error(`SQL failed (${res.status}): ${await res.text()}`)
  }
  return res.json()
}

async function main() {
  const apply = process.argv.includes('--apply')
  const token = process.env.SUPABASE_ACCESS_TOKEN
  if (!token) throw new Error('SUPABASE_ACCESS_TOKEN não definido em env.')
  const projectRef = 'xuxehkhdvjivitduarvb'

  const foodFileA = JSON.parse(
    readFileSync(resolve('scripts/data/curated-phrases-food.json'), 'utf-8'),
  ) as FoodFile
  const foodFileB = JSON.parse(
    readFileSync(resolve('scripts/data/curated-phrases-food-phase-b.json'), 'utf-8'),
  ) as FoodFile
  const foodFile: FoodFile = {
    _language: foodFileA._language,
    _curated_by: foodFileA._curated_by,
    blocks: [...foodFileA.blocks, ...foodFileB.blocks],
  }
  const engagementFile = JSON.parse(
    readFileSync(resolve('scripts/data/curated-phrases-engagement.json'), 'utf-8'),
  ) as EngagementFile

  // Expandir cartesiano food. IMPORTANTE: bloco_id e polaridade vão em
  // COLUNAS dedicadas (não em tags jsonb) — tags são reservadas pra
  // STATE-tags filtradas pelo selector (recomp, protein_low, etc).
  // Colocar metadata de bloco em tags fazia o filtro do selector eliminar
  // todas as candidatas (review #4). Tags fica '{}' = frase universal.
  const foodRows: Array<{
    food_canonical_name: string
    phrase: string
    bloco_id: string
    polaridade: string
  }> = []
  for (const block of foodFile.blocks) {
    for (const alimento of block.alimentos) {
      for (const frase of block.frases) {
        foodRows.push({
          food_canonical_name: normalize(alimento),
          phrase: frase, // mantém {alimento} literal; selector substitui em runtime
          bloco_id: block.bloco_id,
          polaridade: block.polaridade,
        })
      }
    }
  }

  console.log(`[food] cartesiano: ${foodRows.length} linhas (${foodFile.blocks.length} blocos)`)
  console.log(`[engagement] linhas: ${engagementFile.phrases.length}`)

  if (!apply) {
    console.log('\nDRY-RUN (sem --apply). Use --apply pra escrever em prod.')
    // Sanity: amostra primeira linha de cada
    console.log('\nFood (sample):', JSON.stringify(foodRows[0], null, 2))
    console.log('Engagement (sample):', JSON.stringify(engagementFile.phrases[0], null, 2))
    return
  }

  // Limpa entradas antigas do mesmo curated_by (idempotência)
  console.log('\n[1/4] DELETE antigos food_education_phrases curated_by=Roberto…')
  await execSql(
    `DELETE FROM food_education_phrases WHERE curated_by = '${CURATED_BY}';`,
    projectRef,
    token,
  )
  console.log('[2/4] DELETE antigos engagement_phrases curated_by=Roberto…')
  await execSql(
    `DELETE FROM engagement_phrases WHERE curated_by = '${CURATED_BY}';`,
    projectRef,
    token,
  )

  // INSERT food em batches (Supabase Management API tem limite de tamanho de query)
  console.log(`[3/4] INSERT ${foodRows.length} food_education_phrases em batches de 200…`)
  for (let i = 0; i < foodRows.length; i += 200) {
    const batch = foodRows.slice(i, i + 200)
    const values = batch
      .map((r) => {
        const fname = r.food_canonical_name.replace(/'/g, "''")
        const phrase = r.phrase.replace(/'/g, "''")
        const bloco = r.bloco_id.replace(/'/g, "''")
        const pol = r.polaridade.replace(/'/g, "''")
        return `('${fname}', '${phrase}', '{}'::jsonb, '${bloco}', '${pol}', 'pt-BR', '${CURATED_BY}', true, 0)`
      })
      .join(',\n')
    const sql = `INSERT INTO food_education_phrases (food_canonical_name, phrase, tags, bloco_id, polaridade, language, curated_by, active, usage_count) VALUES ${values};`
    await execSql(sql, projectRef, token)
    process.stdout.write(`  inserted ${Math.min(i + 200, foodRows.length)}/${foodRows.length}\r`)
  }
  console.log()

  // INSERT engagement (200 — uma só batch)
  console.log(`[4/4] INSERT ${engagementFile.phrases.length} engagement_phrases…`)
  const engagementValues = engagementFile.phrases
    .map((p) => {
      const phrase = p.phrase.replace(/'/g, "''")
      return `('${phrase}', '${p.slot}', 'pt-BR', '${CURATED_BY}', true, 0)`
    })
    .join(',\n')
  await execSql(
    `INSERT INTO engagement_phrases (phrase, slot, language, curated_by, active, picked_count) VALUES ${engagementValues};`,
    projectRef,
    token,
  )

  // Validação
  console.log('\n[validate] contagem final')
  const foodCount = (await execSql(
    `SELECT count(*)::int as c FROM food_education_phrases WHERE curated_by = '${CURATED_BY}';`,
    projectRef,
    token,
  )) as Array<{ c: number }>
  const engCount = (await execSql(
    `SELECT count(*)::int as c FROM engagement_phrases WHERE curated_by = '${CURATED_BY}';`,
    projectRef,
    token,
  )) as Array<{ c: number }>
  console.log(`  food_education_phrases: ${foodCount[0]?.c}`)
  console.log(`  engagement_phrases:     ${engCount[0]?.c}`)

  console.log('\n✅ Ingest concluído.')
}

main().catch((err) => {
  console.error('❌ Falha:', err)
  process.exit(1)
})
