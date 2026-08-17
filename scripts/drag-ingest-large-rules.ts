/**
 * D-RAG Fase 2.2a: ingerir regras grandes de MÉTODO em method_chunks
 * e arquivar do agent_rules.
 *
 * Critério: só conteúdo de método (treinos, alongamentos, dieta, reavaliação
 * por protocolo, etc) que é relevante em contextos específicos — vai pro RAG.
 * Regras de COMPORTAMENTO always-on (correção, estima-e-registra, engajamento)
 * NÃO entram, ficam ativas no prompt sempre.
 *
 * Roberto autorizou via Eduardo 2026-06-01.
 *
 * Rodar:
 *   set -a; . ./.env.local; set +a
 *   npx tsx scripts/drag-ingest-large-rules.ts
 */
import { createServiceClient } from '@mpp/db'
import { OpenRouterEmbeddings } from '../packages/providers/src/embeddings/openrouter.js'

interface Target {
  slug: string
  protocol: string | null
}

const TARGETS: Target[] = [
  { slug: 'prescricao-de-treinos-para-todos-os-protocolos', protocol: null },
  { slug: 'perguntas-automaticas-ativas-para-todos-os-protocolos', protocol: null },
  { slug: 'sistema-de-gamificacao-para-todos-os-protocolos', protocol: null },
  { slug: 'prescricao-de-alongamentos', protocol: null },
  { slug: 'prescricao-de-dieta-para-todos-os-protocolos', protocol: null },
  { slug: 'ganho-de-massa-muscular-decisao-apos-reavaliacoes', protocol: 'ganho_massa' },
  { slug: 'manutencao-reavaliacao-quinzenal', protocol: 'manutencao' },
  { slug: 'manutencao-medidas-de-ajustes-apos-avaliacao-quinzenal', protocol: 'manutencao' },
  { slug: 'ganho-de-massa-muscular-introducao-de-boas-vindas-ao-protocolo', protocol: 'ganho_massa' },
]

const CHUNK_MAX_CHARS = 2800

function chunkContent(content: string, maxChars: number): string[] {
  if (content.length <= maxChars) return [content]
  // Split por parágrafo (\n\n), respeitando o limite
  const paras = content.split(/\n\n+/)
  const out: string[] = []
  let buf = ''
  for (const p of paras) {
    if (!buf) { buf = p; continue }
    if ((buf + '\n\n' + p).length > maxChars) {
      out.push(buf)
      buf = p
    } else {
      buf += '\n\n' + p
    }
  }
  if (buf) out.push(buf)
  return out
}

async function main() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const openrouterKey = process.env.OPENROUTER_API_KEY
  if (!url || !key) throw new Error('SUPABASE_URL/SERVICE_ROLE_KEY ausente')
  if (!openrouterKey) throw new Error('OPENROUTER_API_KEY ausente')
  const supabase = createServiceClient({ url, serviceRoleKey: key })
  const embeddings = new OpenRouterEmbeddings({ apiKey: openrouterKey, dimensions: 1024 })

  // Pega conteúdo das regras
  const slugList = TARGETS.map((t) => `'${t.slug}'`).join(',')
  const { data: rules } = await supabase
    .from('agent_rules')
    .select('slug, topic, content, status')
    .in('slug', TARGETS.map((t) => t.slug))
  const rulesTyped = (rules ?? []) as Array<{ slug: string; topic: string; content: string; status: string }>

  console.log(`\n── D-RAG: ingerir ${rulesTyped.length} regras grandes ──\n`)

  let totalChunks = 0
  let totalChars = 0
  const archivedSlugs: string[] = []

  for (const target of TARGETS) {
    const rule = rulesTyped.find((r) => r.slug === target.slug)
    if (!rule) {
      console.log(`⚠️  ${target.slug}: não encontrada (skip)`)
      continue
    }
    if (rule.status !== 'active') {
      console.log(`⚠️  ${target.slug}: status=${rule.status} (skip)`)
      continue
    }

    // 1. Verifica se já tem chunks pra esse page_title (idempotência)
    const { count: existing } = await supabase
      .from('method_chunks')
      .select('id', { count: 'exact', head: true })
      .eq('page_title', rule.topic)
    if ((existing ?? 0) > 0) {
      console.log(`✓ ${rule.slug}: já tem ${existing} chunks (skip ingest, vai só arquivar)`)
    } else {
      // 2. Chunka e gera embedding
      const chunks = chunkContent(rule.content, CHUNK_MAX_CHARS)
      console.log(`📝 ${rule.slug}: ${rule.content.length} chars → ${chunks.length} chunks`)

      for (let i = 0; i < chunks.length; i++) {
        const text = chunks[i]!
        // Embedding query inclui page_title pra ajudar match
        const emb = await embeddings.embed(`${rule.topic}\n\n${text}`)
        const { error: insErr } = await supabase
          .from('method_chunks')
          .insert({
            page_title: rule.topic,
            chunk_index: i,
            content: text,
            protocol: target.protocol,
            embedding: emb as unknown as string,
          })
        if (insErr) throw new Error(`insert chunk ${i} de ${rule.slug}: ${insErr.message}`)
        totalChunks++
        totalChars += text.length
        console.log(`   chunk ${i}: ${text.length} chars, embed ✅`)
      }
    }

    // 3. Arquiva a regra
    const { error: updErr } = await supabase
      .from('agent_rules')
      .update({ status: 'archived', updated_at: new Date().toISOString() })
      .eq('slug', rule.slug)
    if (updErr) throw new Error(`archive ${rule.slug}: ${updErr.message}`)
    archivedSlugs.push(rule.slug)
    console.log(`📦 ${rule.slug}: arquivada`)
  }

  // Audit event
  await supabase.from('product_events').insert({
    event: 'admin.drag_ingest_and_archive',
    properties: {
      date: '2026-06-01',
      reason: 'Fase 2.2 D-RAG — ingerir regras grandes de método em method_chunks + arquivar agent_rules. RAG recupera quando relevante via retrieveMethodContext.',
      by: 'Eduardo+Roberto autorizaram',
      n_archived: archivedSlugs.length,
      archived_slugs: archivedSlugs,
      total_chars_ingested: totalChars,
      total_chunks_ingested: totalChunks,
    },
  })
  console.log(`\n✅ Concluído: ${archivedSlugs.length} regras arquivadas, ${totalChunks} chunks ingeridos (${totalChars} chars).`)
}

main().catch((e) => {
  console.error('❌', e)
  process.exit(1)
})
