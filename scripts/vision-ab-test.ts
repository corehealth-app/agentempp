/**
 * A/B vision (Fix #3 Bug Roberto 2026-05-29): alucinação "achocolatado e
 * linguiça" no café do Roberto com gemini-2.5-flash (atual).
 *
 * Roda N modelos via OpenRouter na MESMA foto + MESMO prompt e reporta:
 *  - items identificados + macros estimados
 *  - latência
 *  - tokens + custo USD aproximado
 *
 * Rodar:
 *   set -a; . ./.env.local; set +a
 *   pnpm tsx scripts/vision-ab-test.ts <image_url>
 *   pnpm tsx scripts/vision-ab-test.ts   # usa fotos default (café + almoço)
 */
import { performance } from 'node:perf_hooks'

const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY
if (!OPENROUTER_API_KEY) {
  console.error('OPENROUTER_API_KEY ausente em env')
  process.exit(1)
}

// Prompt CONSERVADOR já em produção (extraído do GeminiVisionProvider).
// Igual ao que cada modelo recebe hoje pro Roberto.
const VISION_PROMPT = `Você está analisando uma foto de COMIDA enviada por um paciente em coaching nutricional.

REGRAS CRÍTICAS:
1. NUNCA invente alimentos. Se não tem 100% de certeza visual de um item, NÃO inclua na lista.
2. Se a imagem está borrada, escura ou ambígua → diga "foto pouco clara" e liste só o que tem certeza.
3. Estime quantidades em GRAMAS apenas se há referência visual clara (prato, garfo, mão). Senão, diga "quantidade incerta".
4. PRESERVE o nome do alimento como aparece visualmente — não troque "ovo mexido" por "ovo cozido", não traduza.
5. Foto de café da manhã típico brasileiro: PROVAVELMENTE leite/café/pão/ovo/queijo/fruta. NÃO assuma achocolatado ou linguiça sem evidência visual clara.

Responda em JSON estrito:
{
  "items": [
    {"food_name": "nome em português", "quantity_g": número_ou_null, "confidence": "alta|média|baixa"}
  ],
  "quality_flag": "ok|foto_pouco_clara|conteudo_ambiguo",
  "notes": "uma frase curta"
}`

interface ModelConfig {
  id: string
  label: string
  pricing: { input: number; output: number } // USD por 1M tokens
}

// Preços do OpenRouter (USD por 1M tokens). Ref: openrouter.ai/models
const MODELS: ModelConfig[] = [
  {
    id: 'google/gemini-2.5-flash',
    label: 'Gemini 2.5 Flash (ATUAL)',
    pricing: { input: 0.075, output: 0.3 },
  },
  {
    id: 'google/gemini-2.5-pro',
    label: 'Gemini 2.5 Pro',
    pricing: { input: 1.25, output: 5.0 },
  },
  {
    id: 'openai/gpt-4o-mini',
    label: 'GPT-4o Mini',
    pricing: { input: 0.15, output: 0.6 },
  },
  {
    id: 'openai/gpt-4o',
    label: 'GPT-4o',
    pricing: { input: 2.5, output: 10.0 },
  },
  {
    id: 'anthropic/claude-sonnet-4.5',
    label: 'Claude Sonnet 4.5',
    pricing: { input: 3.0, output: 15.0 },
  },
]

interface RunResult {
  model: string
  ok: boolean
  latencyMs: number
  promptTokens: number
  completionTokens: number
  costUsd: number
  raw: string
  parsed: unknown
  error?: string
}

async function callModel(model: ModelConfig, imageUrl: string): Promise<RunResult> {
  const start = performance.now()
  try {
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${OPENROUTER_API_KEY}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://agentempp.local',
        'X-Title': 'Vision A/B Test',
      },
      body: JSON.stringify({
        model: model.id,
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: VISION_PROMPT },
              { type: 'image_url', image_url: { url: imageUrl } },
            ],
          },
        ],
        temperature: 0.1,
        max_tokens: 800,
        response_format: { type: 'json_object' },
      }),
    })
    const latencyMs = Math.round(performance.now() - start)
    const json = (await res.json()) as {
      choices?: Array<{ message?: { content?: string } }>
      usage?: { prompt_tokens?: number; completion_tokens?: number }
      error?: { message?: string }
    }
    if (json.error || !json.choices?.[0]?.message?.content) {
      return {
        model: model.label,
        ok: false,
        latencyMs,
        promptTokens: 0,
        completionTokens: 0,
        costUsd: 0,
        raw: '',
        parsed: null,
        error: json.error?.message ?? 'sem content',
      }
    }
    const raw = json.choices[0].message.content
    const promptTokens = json.usage?.prompt_tokens ?? 0
    const completionTokens = json.usage?.completion_tokens ?? 0
    const costUsd =
      (promptTokens * model.pricing.input) / 1_000_000 +
      (completionTokens * model.pricing.output) / 1_000_000
    let parsed: unknown = null
    try {
      parsed = JSON.parse(raw)
    } catch {
      // Alguns retornam json com prefixo ```json
      const m = raw.match(/\{[\s\S]*\}/)
      if (m) {
        try {
          parsed = JSON.parse(m[0])
        } catch {
          /* deixa como string */
        }
      }
    }
    return {
      model: model.label,
      ok: true,
      latencyMs,
      promptTokens,
      completionTokens,
      costUsd,
      raw,
      parsed,
    }
  } catch (err) {
    return {
      model: model.label,
      ok: false,
      latencyMs: Math.round(performance.now() - start),
      promptTokens: 0,
      completionTokens: 0,
      costUsd: 0,
      raw: '',
      parsed: null,
      error: err instanceof Error ? err.message : String(err),
    }
  }
}

function formatItems(parsed: unknown): string {
  if (!parsed || typeof parsed !== 'object') return '(parse falhou)'
  const p = parsed as { items?: Array<{ food_name?: string; quantity_g?: number | null; confidence?: string }>; quality_flag?: string; notes?: string }
  const items = (p.items ?? [])
    .map((it) => `  • ${it.food_name ?? '?'} (${it.quantity_g ?? '?'}g) [${it.confidence ?? '?'}]`)
    .join('\n')
  return `  quality: ${p.quality_flag ?? '?'}\n${items}\n  notes: ${p.notes ?? ''}`
}

async function runOnImage(url: string, label: string) {
  console.log(`\n${'═'.repeat(78)}`)
  console.log(`📸 FOTO: ${label}`)
  console.log(`   URL: ${url}`)
  console.log(`${'═'.repeat(78)}\n`)

  // Roda todos em paralelo
  const results = await Promise.all(MODELS.map((m) => callModel(m, url)))

  for (const r of results) {
    console.log(`\n── ${r.model} ──`)
    if (!r.ok) {
      console.log(`  ❌ ERRO: ${r.error}`)
      continue
    }
    console.log(`  ⏱  ${r.latencyMs}ms · 📊 ${r.promptTokens}in / ${r.completionTokens}out · 💰 $${r.costUsd.toFixed(6)}`)
    console.log(formatItems(r.parsed))
  }

  // Sumário comparativo
  console.log(`\n📊 SUMÁRIO (${label}):`)
  console.log('  modelo                          latência   custo      items')
  for (const r of results) {
    const items = (r.parsed as { items?: unknown[] } | null)?.items?.length ?? 0
    console.log(
      `  ${r.model.padEnd(30)}  ${String(r.latencyMs).padStart(5)}ms  $${r.costUsd.toFixed(6)}  ${items} items`,
    )
  }
}

async function main() {
  const cliUrl = process.argv[2]
  const photos: Array<{ url: string; label: string }> = cliUrl
    ? [{ url: cliUrl, label: 'CLI input' }]
    : [
        // Café da manhã brasileiro típico (ovo, leite, pão, queijo)
        {
          url: 'https://images.unsplash.com/photo-1533089860892-a7c6f0a88666?w=800',
          label: 'Café da manhã (ovo + pão + queijo + suco)',
        },
        // Prato de comida brasileira típica (arroz, feijão, carne)
        {
          url: 'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=800',
          label: 'Refeição misturada (cardápio brasileiro)',
        },
      ]

  for (const photo of photos) {
    await runOnImage(photo.url, photo.label)
  }

  console.log(`\n${'═'.repeat(78)}`)
  console.log('FIM. Mande uma foto de café/refeição REAL pro Bot pra teste mais fiel.')
  console.log('Pode reaproveitar este script: pnpm tsx scripts/vision-ab-test.ts <url>')
  console.log(`${'═'.repeat(78)}`)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
