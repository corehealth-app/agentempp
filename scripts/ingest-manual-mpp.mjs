#!/usr/bin/env node
// Ingestão do Manual MPP NOVO (Roberto enviou 2026-06-11) em method_chunks.
// Lê 1 arquivo markdown, parseia seções `## Title`, chunka, gera embeddings
// via OpenRouter text-embedding-3-large (1024d) e insere em method_chunks.
//
// Uso: node scripts/ingest-manual-mpp.mjs /tmp/manual-mpp-novo.md
import { readFileSync } from 'node:fs'

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY
const OR_KEY = process.env.OPENROUTER_API_KEY
const FILE_PATH = process.argv[2] || '/tmp/manual-mpp-novo.md'
const MAX_CHARS = 3000

if (!SUPABASE_URL || !SERVICE_KEY || !OR_KEY) {
  console.error('faltam env: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / OPENROUTER_API_KEY')
  process.exit(1)
}

const raw = readFileSync(FILE_PATH, 'utf-8')

// Parse: divide por `## ` heading
const sections = []
const lines = raw.split('\n')
let current = null
for (const line of lines) {
  const m = line.match(/^##\s+(.+?)\s*$/)
  if (m) {
    if (current) sections.push(current)
    current = { title: m[1].trim(), body: [] }
  } else if (current) {
    current.body.push(line)
  }
}
if (current) sections.push(current)

console.log(`Parseadas ${sections.length} seções de ${FILE_PATH}`)

function chunkText(text) {
  if (text.length <= MAX_CHARS) return [text]
  const parts = []
  for (let i = 0; i < text.length; i += MAX_CHARS) parts.push(text.slice(i, i + MAX_CHARS))
  return parts
}

async function embed(text) {
  const r = await fetch('https://openrouter.ai/api/v1/embeddings', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OR_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'openai/text-embedding-3-large',
      input: text,
      dimensions: 1024,
    }),
  })
  if (!r.ok) {
    const t = await r.text().catch(() => '')
    throw new Error(`embed falhou: ${r.status} ${t.slice(0, 200)}`)
  }
  const j = await r.json()
  return j.data[0].embedding
}

async function insertChunk({ pageTitle, content, embedding, chunkIdx }) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/method_chunks`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify({
      page_title: pageTitle,
      chunk_index: chunkIdx,
      content,
      embedding,
      protocol: null,
    }),
  })
  if (!r.ok) {
    const t = await r.text().catch(() => '')
    throw new Error(`insert falhou: ${r.status} ${t.slice(0, 300)}`)
  }
}

let total = 0
let failed = 0
for (const sec of sections) {
  const body = sec.body.join('\n').trim()
  if (body.length < 50) {
    console.log(`  → skip "${sec.title}" (body curto)`)
    continue
  }
  const chunks = chunkText(`${sec.title}\n\n${body}`)
  for (let i = 0; i < chunks.length; i++) {
    try {
      const emb = await embed(chunks[i])
      await insertChunk({
        pageTitle: sec.title,
        content: chunks[i],
        embedding: emb,
        chunkIdx: i,
      })
      total++
      process.stdout.write('.')
    } catch (e) {
      failed++
      console.error(`\n❌ "${sec.title}" chunk ${i}: ${e.message}`)
    }
  }
}
console.log(`\nIngest ok: ${total} chunks (${failed} falhas)`)
