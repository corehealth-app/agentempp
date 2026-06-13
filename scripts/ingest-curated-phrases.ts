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
  // Fase C: +15 frases por bloco (parcial). C2 cobre blocos que não couberam em C.
  // Estrutura compartilhada com A/B (mesmo bloco_id agrupa frases adicionais).
  const foodFileC = JSON.parse(
    readFileSync(resolve('scripts/data/curated-phrases-food-phase-c.json'), 'utf-8'),
  ) as FoodFile
  const foodFileC2 = JSON.parse(
    readFileSync(resolve('scripts/data/curated-phrases-food-phase-c2.json'), 'utf-8'),
  ) as FoodFile
  // Fase D: +15 frases nos 12 blocos pendentes (chegar a 30/bloco em TODOS).
  const foodFileD = JSON.parse(
    readFileSync(resolve('scripts/data/curated-phrases-food-phase-d.json'), 'utf-8'),
  ) as FoodFile
  // Fase E: +15 frases nos 8 blocos C+C2 (chegar a 45/bloco em prioritários).
  const foodFileE = JSON.parse(
    readFileSync(resolve('scripts/data/curated-phrases-food-phase-e.json'), 'utf-8'),
  ) as FoodFile
  const foodFile: FoodFile = {
    _language: foodFileA._language,
    _curated_by: foodFileA._curated_by,
    blocks: [
      ...foodFileA.blocks,
      ...foodFileB.blocks,
      ...foodFileC.blocks,
      ...foodFileC2.blocks,
      ...foodFileD.blocks,
      ...foodFileE.blocks,
    ],
  }
  const engagementFile = JSON.parse(
    readFileSync(resolve('scripts/data/curated-phrases-engagement.json'), 'utf-8'),
  ) as EngagementFile

  // Expandir cartesiano food. Dedup via fingerprint (bloco+alimento+phrase)
  // evita gravar linhas duplicadas quando fases copiaram a mesma frase
  // (review HIGH: Fase D duplicou 15 frases da B; E duplicou 3). Sem dedup,
  // selector ordena LRU e o paciente recebe a mesma string com IDs diferentes.
  const foodRows: Array<{
    food_canonical_name: string
    phrase: string
    bloco_id: string
    polaridade: string
  }> = []
  const seenFingerprints = new Set<string>()
  let duplicatasDescartadas = 0
  for (const block of foodFile.blocks) {
    for (const alimento of block.alimentos) {
      const canonical = normalize(alimento)
      for (const frase of block.frases) {
        const fingerprint = `${block.bloco_id}|${canonical}|${frase}`
        if (seenFingerprints.has(fingerprint)) {
          duplicatasDescartadas++
          continue
        }
        seenFingerprints.add(fingerprint)
        foodRows.push({
          food_canonical_name: canonical,
          phrase: frase, // mantém {alimento} literal; selector substitui em runtime
          bloco_id: block.bloco_id,
          polaridade: block.polaridade,
        })
      }
    }
  }
  if (duplicatasDescartadas > 0) {
    console.log(`[food] dedup: ${duplicatasDescartadas} duplicatas descartadas`)
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
