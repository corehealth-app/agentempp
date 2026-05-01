/**
 * Importação one-shot das 88 regras + 6 configs do Notion (legado) para o Postgres.
 *
 * Uso:
 *   pnpm --filter @mpp/scripts seed:notion
 *
 * Idempotente: usa upsert por slug (rules) e (stage, version) (configs).
 * Marca tudo como status='active' e popula a primeira versão automaticamente
 * via trigger de versionamento.
 */
import { createClient } from '@supabase/supabase-js'
import type { Database } from '@mpp/db'

// ----------------------------------------------------------------------------
// Tipos
// ----------------------------------------------------------------------------
type RuleTipo = 'recomposicao' | 'ganho_massa' | 'manutencao' | 'coleta_dados' | 'regras_gerais'

type AgentStage =
  | 'coleta_dados'
  | 'recomposicao'
  | 'ganho_massa'
  | 'manutencao'
  | 'analista_diario'
  | 'engajamento'

interface RuleRecord {
  notion_id: string
  topic: string
  slug: string
  tipo: RuleTipo
  content: string
  display_order: number
  token_estimate: number
}

interface ConfigRecord {
  notion_id: string
  stage: AgentStage
  name: string
  version: string
  model: string
  temperature: number
  max_tokens: number
  wait_seconds: number
  prompt_image: string | null
  notes: string | null
}

// ----------------------------------------------------------------------------
// Mapeamentos Notion → schema Postgres
// ----------------------------------------------------------------------------
const TIPO_MAP: Record<string, RuleTipo> = {
  'Recomposição Corporal': 'recomposicao',
  'Ganho De Massa': 'ganho_massa',
  'Manutenção': 'manutencao',
  'Coleta de Dados': 'coleta_dados',
  'Regras Gerais': 'regras_gerais',
}

const STAGE_MAP: Record<string, AgentStage> = {
  'Coleta de Dados': 'coleta_dados',
  'Recomposição Corporal': 'recomposicao',
  'Ganho de Massa': 'ganho_massa',
  'Manutenção': 'manutencao',
  'Analista Diário': 'analista_diario',
  'Engajamento': 'engajamento',
}

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------
const NOTION_VERSION = '2022-06-28'

function env(key: string): string {
  const v = process.env[key]
  if (!v) throw new Error(`Missing env var: ${key}`)
  return v
}

function slugify(s: string): string {
  return s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 80)
}

function richTextToString(rt: Array<{ plain_text?: string }> | undefined): string {
  if (!rt) return ''
  return rt.map((t) => t.plain_text ?? '').join('')
}

async function notionFetch(path: string, init?: RequestInit) {
  const res = await fetch(`https://api.notion.com/v1${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${env('NOTION_TOKEN')}`,
      'Notion-Version': NOTION_VERSION,
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
  })
  if (!res.ok) {
    const body = await res.text()
    throw new Error(`Notion API error ${res.status} ${path}: ${body}`)
  }
  return res.json() as Promise<Record<string, unknown>>
}

async function queryDatabaseAll(
  databaseId: string,
  filter?: Record<string, unknown>,
): Promise<Array<Record<string, unknown>>> {
  const results: Array<Record<string, unknown>> = []
  let cursor: string | undefined
  do {
    const body: Record<string, unknown> = { page_size: 100 }
    if (cursor) body.start_cursor = cursor
    if (filter) body.filter = filter
    const res = (await notionFetch(`/databases/${databaseId}/query`, {
      method: 'POST',
      body: JSON.stringify(body),
    })) as { results: Array<Record<string, unknown>>; has_more: boolean; next_cursor: string }
    results.push(...res.results)
    cursor = res.has_more ? res.next_cursor : undefined
  } while (cursor)
  return results
}

// ----------------------------------------------------------------------------
// Extração de regras
// ----------------------------------------------------------------------------
async function fetchAllRules(): Promise<RuleRecord[]> {
  const dbId = env('NOTION_DB_RULES')
  console.log(`📥 Buscando regras de Notion DB ${dbId}…`)
  const pages = await queryDatabaseAll(dbId)
  console.log(`   ${pages.length} páginas retornadas`)

  const rules: RuleRecord[] = []
  let idx = 0
  for (const page of pages) {
    const props = page.properties as Record<string, any>
    const topic = props.Topic?.title?.[0]?.plain_text?.trim()
    const tipoRaw = props.Tipo?.select?.name?.trim()
    const content = richTextToString(props.Content?.rich_text).trim()

    if (!topic || !tipoRaw || !content) {
      console.warn(`   ⚠ Pulada página sem campos: ${page.id} topic=${topic} tipo=${tipoRaw}`)
      continue
    }

    const tipo = TIPO_MAP[tipoRaw]
    if (!tipo) {
      console.warn(`   ⚠ Tipo desconhecido: "${tipoRaw}" em ${topic}`)
      continue
    }

    rules.push({
      notion_id: page.id as string,
      topic,
      slug: slugify(topic),
      tipo,
      content,
      display_order: idx,
      token_estimate: Math.ceil(content.length / 4),
    })
    idx++
  }

  // Detecta slugs duplicados (raro, mas possível com topics muito parecidos)
  const slugCounts = new Map<string, number>()
  for (const r of rules) {
    slugCounts.set(r.slug, (slugCounts.get(r.slug) ?? 0) + 1)
  }
  const counter = new Map<string, number>()
  for (const r of rules) {
    if ((slugCounts.get(r.slug) ?? 0) > 1) {
      const n = (counter.get(r.slug) ?? 0) + 1
      counter.set(r.slug, n)
      r.slug = `${r.slug}-${n}`
    }
  }

  return rules
}

// ----------------------------------------------------------------------------
// Extração de configs
// ----------------------------------------------------------------------------
async function fetchAllConfigs(): Promise<ConfigRecord[]> {
  const dbId = env('NOTION_DB_CONFIGS')
  console.log(`📥 Buscando configs de Notion DB ${dbId}…`)
  const pages = await queryDatabaseAll(dbId, {
    property: 'Status',
    select: { equals: 'Active' },
  })
  console.log(`   ${pages.length} configs ativas retornadas`)

  const configs: ConfigRecord[] = []
  for (const page of pages) {
    const props = page.properties as Record<string, any>
    const stageRaw = props.Stage?.select?.name?.trim()
    const stage = STAGE_MAP[stageRaw]
    if (!stage) {
      console.warn(`   ⚠ Stage desconhecido: "${stageRaw}"`)
      continue
    }

    const name = props['Config Name']?.title?.[0]?.plain_text?.trim() ?? stage
    const version = richTextToString(props.Version?.rich_text).trim() || 'v1.0.0'
    const model = props.Model?.select?.name?.trim() ?? ''
    const temperature = props.Temperature?.number ?? 0.4
    const maxTokens = props['Max Tokens']?.number ?? 8192
    const waitSeconds = props['Wait Seconds Response']?.number ?? 10
    const promptImage = richTextToString(props['Prompt System Image']?.rich_text).trim() || null
    const notes = null

    configs.push({
      notion_id: page.id as string,
      stage,
      name,
      version,
      model,
      temperature: Number(temperature),
      max_tokens: Number(maxTokens),
      wait_seconds: Number(waitSeconds),
      prompt_image: promptImage,
      notes,
    })
  }

  return configs
}

// ----------------------------------------------------------------------------
// Seed para Postgres
// ----------------------------------------------------------------------------
async function seedToSupabase(rules: RuleRecord[], configs: ConfigRecord[]) {
  const supabase = createClient<Database>(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  console.log('\n🧹 Limpando agent_rules e agent_configs (greenfield)…')
  await supabase.from('agent_configs_versions').delete().neq('version_num', -1)
  await supabase.from('agent_rules_versions').delete().neq('version_num', -1)
  await supabase.from('agent_configs').delete().neq('id', '00000000-0000-0000-0000-000000000000')
  await supabase.from('agent_rules').delete().neq('id', '00000000-0000-0000-0000-000000000000')

  console.log(`\n📤 Inserindo ${rules.length} regras…`)
  const ruleRows = rules.map((r) => ({
    topic: r.topic,
    slug: r.slug,
    tipo: r.tipo,
    content: r.content,
    display_order: r.display_order,
    status: 'active' as const,
    token_estimate: r.token_estimate,
  }))

  // Insere em chunks de 50 para não estourar payload size
  for (let i = 0; i < ruleRows.length; i += 50) {
    const chunk = ruleRows.slice(i, i + 50)
    const { error } = await supabase.from('agent_rules').insert(chunk)
    if (error) {
      console.error(`   ❌ Erro chunk ${i}:`, error.message)
      throw error
    }
    console.log(`   ✓ ${Math.min(i + 50, ruleRows.length)}/${ruleRows.length}`)
  }

  console.log(`\n📤 Inserindo ${configs.length} configs…`)
  for (const cfg of configs) {
    const { error } = await supabase.from('agent_configs').insert({
      stage: cfg.stage,
      name: cfg.name,
      version: cfg.version,
      model: cfg.model,
      temperature: cfg.temperature,
      max_tokens: cfg.max_tokens,
      wait_seconds: cfg.wait_seconds,
      prompt_image: cfg.prompt_image,
      status: 'active',
      rollout_percent: 100,
      notes: cfg.notes,
    })
    if (error) {
      console.error(`   ❌ Erro config ${cfg.stage}:`, error.message)
      throw error
    }
    console.log(`   ✓ ${cfg.stage} (${cfg.name} ${cfg.version})`)
  }
}

// ----------------------------------------------------------------------------
// Verificação
// ----------------------------------------------------------------------------
async function verify() {
  const supabase = createClient<Database>(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  console.log('\n🔍 Verificação…')

  const { count: rulesCount } = await supabase
    .from('agent_rules')
    .select('*', { count: 'exact', head: true })
    .eq('status', 'active')
  console.log(`   ${rulesCount} regras ativas`)

  const { data: byTipo } = await supabase
    .from('agent_rules')
    .select('tipo')
    .eq('status', 'active')
  const counts = (byTipo ?? []).reduce<Record<string, number>>(
    (acc: Record<string, number>, r: { tipo: string }) => {
      acc[r.tipo] = (acc[r.tipo] ?? 0) + 1
      return acc
    },
    {},
  )
  for (const [t, n] of Object.entries(counts)) {
    console.log(`     ${t.padEnd(20)} ${n}`)
  }

  const { count: configsCount } = await supabase
    .from('agent_configs')
    .select('*', { count: 'exact', head: true })
    .eq('status', 'active')
  console.log(`   ${configsCount} configs ativas`)

  const { count: rvCount } = await supabase
    .from('agent_rules_versions')
    .select('*', { count: 'exact', head: true })
  console.log(`   ${rvCount} versões de regra (esperado = nº regras na primeira inserção)`)
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------
async function main() {
  console.log('━━━ Seed Notion → Postgres ━━━\n')
  const rules = await fetchAllRules()
  const configs = await fetchAllConfigs()

  console.log(`\n📊 Resumo extração:`)
  console.log(`   Regras: ${rules.length}`)
  console.log(`   Configs: ${configs.length}`)

  await seedToSupabase(rules, configs)
  await verify()

  console.log('\n✅ Concluído.')
}

main().catch((err) => {
  console.error('💥 Falha:', err)
  process.exit(1)
})
