// Ingestão do método MPP na base RAG (method_chunks). Sub-projeto D — fundação.
// Lê páginas .md do export Notion, gera embeddings (OpenRouter text-embedding-3-large
// 1024d) e insere em method_chunks. DORMENTE: nada consome ainda.
//
// Uso: node scripts/ingest-method-rag.mjs <dir-do-metodo>
//   (default: /tmp/mpp-original — extrair o ExportBlock-*.zip antes)
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'

const SUPABASE_URL = process.env.SUPABASE_URL
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY
const OR_KEY = process.env.OPENROUTER_API_KEY
const ROOT = process.argv[2] || '/tmp/mpp-original'
const MAX_CHARS = 3000

if (!SUPABASE_URL || !SERVICE_KEY || !OR_KEY) {
  console.error('faltam env: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / OPENROUTER_API_KEY')
  process.exit(1)
}

// coleta recursiva de .md, ignorando Trash/bkp
function collectMd(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name)
    if (/Trash|\[bkp\]/i.test(p)) continue
    const st = statSync(p)
    if (st.isDirectory()) collectMd(p, out)
    else if (name.endsWith('.md')) out.push(p)
  }
  return out
}

function cleanTitle(path) {
  const base = path.split('/').pop().replace(/\.md$/, '')
  return base.replace(/\s+[0-9a-f]{32}.*$/i, '').trim()
}

function chunk(text) {
  if (text.length <= MAX_CHARS) return [text]
  const parts = []
  for (let i = 0; i < text.length; i += MAX_CHARS) parts.push(text.slice(i, i + MAX_CHARS))
  return parts
}

async function embed(text) {
  const r = await fetch('https://openrouter.ai/api/v1/embeddings', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OR_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'openai/text-embedding-3-large', input: text, dimensions: 1024 }),
  })
  if (!r.ok) throw new Error(`embed ${r.status}: ${(await r.text()).slice(0, 200)}`)
  const j = await r.json()
  return j.data[0].embedding
}

async function insert(rows) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/method_chunks`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(rows),
  })
  if (!r.ok) throw new Error(`insert ${r.status}: ${(await r.text()).slice(0, 200)}`)
}

const files = collectMd(ROOT)
console.log(`${files.length} páginas .md encontradas`)
let total = 0
let pages = 0
for (const f of files) {
  const raw = readFileSync(f, 'utf8').trim()
  if (raw.length < 40) continue // pula páginas vazias/índice
  const title = cleanTitle(f)
  const protocol = /recomposi/i.test(title)
    ? 'recomposicao'
    : /ganho de massa/i.test(title)
      ? 'ganho_massa'
      : /manuten/i.test(title)
        ? 'manutencao'
        : null
  const chunks = chunk(raw)
  const rows = []
  for (let i = 0; i < chunks.length; i++) {
    const emb = await embed(`${title}\n\n${chunks[i]}`)
    rows.push({
      page_title: title,
      chunk_index: i,
      content: chunks[i],
      protocol,
      embedding: `[${emb.join(',')}]`,
    })
    total++
  }
  await insert(rows)
  pages++
  if (pages % 20 === 0) console.log(`  ${pages} páginas / ${total} chunks...`)
}
console.log(`OK: ${pages} páginas, ${total} chunks ingeridos em method_chunks.`)
