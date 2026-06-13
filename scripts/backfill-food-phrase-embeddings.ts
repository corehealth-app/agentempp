/**
 * Backfill embeddings em food_education_phrases.food_name_embedding.
 *
 * Eficiência: embeda APENAS os food_canonical_name únicos (~200) e replica
 * o vetor pra todas as linhas que compartilham o mesmo nome (cada nome
 * aparece em ~50 frases). Reduz custo de 10208 embeddings → 200 chamadas.
 *
 * Modelo: openai/text-embedding-3-large com 1024 dims (compatível com
 * coluna vector(1024) e infra já usada em method_chunks).
 *
 * Uso:
 *   set -a && . ./.env.local && set +a
 *   npx tsx scripts/backfill-food-phrase-embeddings.ts             # dry-run
 *   npx tsx scripts/backfill-food-phrase-embeddings.ts --apply     # aplica
 */
// Inlinado pra evitar dep do workspace package (script standalone via npx tsx)
class OpenRouterEmbeddings {
  private apiKey: string
  private model: string
  private dimensions: number
  constructor(cfg: { apiKey: string; model?: string; dimensions?: number }) {
    this.apiKey = cfg.apiKey
    this.model = cfg.model ?? 'openai/text-embedding-3-large'
    this.dimensions = cfg.dimensions ?? 1024
  }
  async embedBatch(texts: string[]): Promise<number[][]> {
    if (texts.length === 0) return []
    const res = await fetch('https://openrouter.ai/api/v1/embeddings', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://github.com/corehealth-app/agentempp',
        'X-Title': 'Agente MPP',
      },
      body: JSON.stringify({
        model: this.model,
        input: texts,
        dimensions: this.dimensions,
      }),
    })
    if (!res.ok) throw new Error(`Embeddings API ${res.status}: ${await res.text()}`)
    const j = (await res.json()) as { data: Array<{ embedding: number[] }> }
    return j.data.map((d) => d.embedding)
  }
}

async function execSql(sql: string, projectRef: string, token: string): Promise<unknown> {
  const res = await fetch(`https://api.supabase.com/v1/projects/${projectRef}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  })
  if (!res.ok) throw new Error(`SQL failed (${res.status}): ${await res.text()}`)
  return res.json()
}

async function main() {
  const apply = process.argv.includes('--apply')
  const token = process.env.SUPABASE_ACCESS_TOKEN
  const orKey = process.env.OPENROUTER_API_KEY
  if (!token) throw new Error('SUPABASE_ACCESS_TOKEN ausente')
  if (!orKey) throw new Error('OPENROUTER_API_KEY ausente')
  const projectRef = 'xuxehkhdvjivitduarvb'

  // 1. Lista food_canonical_name únicos sem embedding
  console.log('[1/3] Carregando food_canonical_name únicos sem embedding…')
  const names = (await execSql(
    `SELECT DISTINCT food_canonical_name FROM food_education_phrases
     WHERE food_name_embedding IS NULL AND active = true
     ORDER BY food_canonical_name;`,
    projectRef,
    token,
  )) as Array<{ food_canonical_name: string }>
  console.log(`  ${names.length} nomes únicos pendentes`)
  if (names.length === 0) {
    console.log('Nada a fazer.')
    return
  }

  if (!apply) {
    console.log(`\nDRY-RUN: ${names.length} nomes seriam embedded (~$${(names.length * 5 * 0.00002 / 1000).toFixed(6)}).`)
    console.log('Amostra dos 5 primeiros:', names.slice(0, 5).map((n) => n.food_canonical_name))
    return
  }

  // 2. Embeddings em batch (OpenAI suporta até 2048 inputs por call)
  console.log('[2/3] Gerando embeddings…')
  const embeddings = new OpenRouterEmbeddings({ apiKey: orKey, dimensions: 1024 })
  const BATCH = 200
  const nameToVec = new Map<string, number[]>()
  for (let i = 0; i < names.length; i += BATCH) {
    const batch = names.slice(i, i + BATCH)
    const texts = batch.map((n) => n.food_canonical_name)
    const vecs = await embeddings.embedBatch(texts)
    for (let j = 0; j < batch.length; j++) {
      const name = batch[j]?.food_canonical_name
      const vec = vecs[j]
      if (name && vec) nameToVec.set(name, vec)
    }
    process.stdout.write(`  embedded ${Math.min(i + BATCH, names.length)}/${names.length}\r`)
  }
  console.log()

  // 3. UPDATE em batches: cada nome único atualiza todas suas linhas
  console.log('[3/3] Atualizando food_name_embedding…')
  let updated = 0
  for (const [name, vec] of nameToVec) {
    const vecLit = `'[${vec.join(',')}]'::vector`
    const sql = `UPDATE food_education_phrases
                 SET food_name_embedding = ${vecLit}
                 WHERE food_canonical_name = $$${name.replace(/\$/g, '$$$$')}$$
                   AND food_name_embedding IS NULL;`
    await execSql(sql, projectRef, token)
    updated++
    if (updated % 20 === 0) {
      process.stdout.write(`  updated ${updated}/${nameToVec.size} nomes\r`)
    }
  }
  console.log(`\n✅ Backfill concluído: ${nameToVec.size} nomes únicos embedados.`)

  // Verificação
  const remaining = (await execSql(
    `SELECT count(*)::int c FROM food_education_phrases WHERE food_name_embedding IS NULL AND active = true;`,
    projectRef,
    token,
  )) as Array<{ c: number }>
  console.log(`Linhas sem embedding: ${remaining[0]?.c ?? '?'}`)
}

main().catch((err) => {
  console.error('❌ Falha:', err)
  process.exit(1)
})
