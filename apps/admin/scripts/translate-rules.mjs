/**
 * Traduz as ~8 rules mais críticas (tom/persona/cadência) para EN e ES.
 * Outras rules ficam em pt-BR e o resolve_system_prompt faz fallback.
 *
 * Idempotente: se já existe rule com mesmo slug + language, skip.
 */
import OpenAI from 'openai'
import { createClient } from '@supabase/supabase-js'

const svc = createClient(
  process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false } },
)

const { data: cred } = await svc
  .from('service_credentials')
  .select('value')
  .eq('service', 'openrouter')
  .eq('key_name', 'api_key')
  .eq('is_active', true)
  .maybeSingle()
const llm = new OpenAI({
  apiKey: cred.value,
  baseURL: 'https://openrouter.ai/api/v1',
})

// Slugs críticos que afetam DIRETAMENTE o tom da resposta ao paciente
const CRITICAL_SLUGS = [
  'persona-master-dr-roberto-amigo-coach',
  'quando-mostrar-balanco-diario',
  'saudacoes-variadas',
  'decisoes-com-confirmacao',
  'idioma-do-paciente',
  'confirmacao-pais-residencia',
]

const LANGUAGES = [
  { code: 'en', label: 'English (US-friendly, informal coach tone)' },
  { code: 'es', label: 'Español (Latino-American, informal "tú")' },
]

const { data: rules } = await svc
  .from('agent_rules')
  .select('id, slug, topic, content, tipo, display_order, status, language')
  .in('slug', CRITICAL_SLUGS)
  .eq('language', 'pt-BR')
  .eq('status', 'active')

console.log(`${rules.length} rules pt-BR carregadas`)

let translated = 0
let skipped = 0
let failed = 0

for (const rule of rules) {
  for (const lang of LANGUAGES) {
    // Slug fica o mesmo entre idiomas — UNIQUE é (slug, language) implícito?
    // Como o schema tem UNIQUE em slug, precisa diferenciar por language.
    // Solução: slug vira slug + '-' + lang.code (ex: persona-master-...-en)
    const newSlug = `${rule.slug}-${lang.code}`

    const { data: dup } = await svc
      .from('agent_rules')
      .select('id')
      .eq('slug', newSlug)
      .maybeSingle()
    if (dup) {
      console.log(`  · skip ${newSlug} (já existe)`)
      skipped++
      continue
    }

    console.log(`  → traduzindo ${rule.slug} pra ${lang.code}...`)
    let translatedContent
    let translatedTopic
    try {
      const r = await llm.chat.completions.create({
        model: 'x-ai/grok-4.1-fast',
        temperature: 0.3,
        max_tokens: 4000,
        messages: [
          {
            role: 'system',
            content: `Você traduz instruções para um agente nutricional de IA. Traduz para ${lang.label}.

Regras de tradução:
- Mantém estrutura markdown idêntica (##, -, **, etc.)
- Mantém placeholders entre {chaves} ou \`backticks\` LITERAIS, não traduz
- Adapta exemplos pra cultura local (ex: "almoço com arroz e feijão" pra US vira "lunch with chicken and rice")
- Tom: amigo coach, primeira pessoa, informal mas técnico quando preciso
- Mantém referências a tools (\`pausar_agente\`, \`confirma_pais_residencia\` etc.) com nome IDÊNTICO ao original
- Personas: "Dr. Roberto Menescal" mantém pra ES; vira "Dr. Robert Menescal" pra EN
- "Método MPP" ou "Método MPP (Muscular Power Plant)" mantém literal

Retorne JSON: {"topic": "...", "content": "..."}`,
          },
          {
            role: 'user',
            content: `Topic original (PT-BR): ${rule.topic}\n\nContent original (PT-BR):\n\n${rule.content}\n\nTraduza pra ${lang.label}.`,
          },
        ],
        response_format: { type: 'json_object' },
      })
      const out = JSON.parse(r.choices[0].message.content)
      translatedContent = out.content
      translatedTopic = out.topic
    } catch (e) {
      console.error(`    ✗ LLM falhou: ${e.message}`)
      failed++
      continue
    }

    if (!translatedContent) {
      console.error(`    ✗ conteúdo vazio`)
      failed++
      continue
    }

    const { error } = await svc.from('agent_rules').insert({
      slug: newSlug,
      topic: translatedTopic ?? rule.topic,
      tipo: rule.tipo,
      content: translatedContent,
      display_order: rule.display_order,
      status: 'active',
      language: lang.code,
    })
    if (error) {
      console.error(`    ✗ insert: ${error.message}`)
      failed++
    } else {
      console.log(`    ✓ inserida ${newSlug} (${translatedContent.length} chars)`)
      translated++
    }
  }
}

console.log(`\nResultado: traduzidas=${translated} skipped=${skipped} failed=${failed}`)
