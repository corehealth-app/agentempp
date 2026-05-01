/**
 * CLI de chat para conversar com o agente sem WhatsApp.
 *
 * Uso:
 *   pnpm --filter @mpp/cli chat
 *
 * Comandos especiais:
 *   /from <wpp>     muda o número simulado (default 5511999999999)
 *   /reset          apaga o usuário atual e suas mensagens
 *   /status         mostra perfil + progresso
 *   /quit           sai
 */
import { processMessage } from '@mpp/agent'
import { createServiceClient } from '@mpp/db'
import { ConsoleProvider, OpenRouterLLM } from '@mpp/providers'
import * as readline from 'node:readline/promises'
import { stdin as input, stdout as output } from 'node:process'

const ANSI = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  cyan: '\x1b[36m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  green: '\x1b[32m',
}

function env(key: string): string {
  const v = process.env[key]
  if (!v) {
    console.error(`${ANSI.red}Missing env: ${key}${ANSI.reset}`)
    process.exit(1)
  }
  return v
}

function header() {
  console.log(`${ANSI.bold}${ANSI.cyan}━━━ Agente MPP — CLI Chat ━━━${ANSI.reset}`)
  console.log(`${ANSI.dim}Conversa local com o agente. WhatsApp ainda não plugado.${ANSI.reset}`)
  console.log(`${ANSI.dim}Comandos: /from <wpp>, /status, /reset, /quit${ANSI.reset}`)
  console.log()
}

async function showStatus(supabase: ReturnType<typeof createServiceClient>, wpp: string) {
  const { data: user } = await supabase
    .from('users')
    .select('id, name, status, created_at')
    .eq('wpp', wpp)
    .maybeSingle()
  if (!user) {
    console.log(`${ANSI.yellow}(usuário ${wpp} ainda não existe)${ANSI.reset}\n`)
    return
  }
  const [{ data: profile }, { data: progress }] = await Promise.all([
    supabase.from('user_profiles').select('*').eq('user_id', user.id).maybeSingle(),
    supabase.from('user_progress').select('*').eq('user_id', user.id).maybeSingle(),
  ])
  console.log(`${ANSI.cyan}━━ Status de ${wpp} ━━${ANSI.reset}`)
  console.log(`  Nome:       ${user.name ?? '(?)'}`)
  console.log(`  Protocolo:  ${profile?.current_protocol ?? '(não definido)'}`)
  console.log(`  Onboarding: step=${profile?.onboarding_step}/11 done=${profile?.onboarding_completed}`)
  console.log(`  Sexo:       ${profile?.sex ?? '?'}`)
  console.log(`  Peso:       ${profile?.weight_kg ?? '?'} kg`)
  console.log(`  BF%:        ${profile?.body_fat_percent ?? '?'}`)
  console.log(`  XP:         ${progress?.xp_total ?? 0} (level ${progress?.level ?? 1})`)
  console.log(`  Streak:     ${progress?.current_streak ?? 0} dias`)
  console.log(`  Blocos:     ${progress?.blocks_completed ?? 0}`)
  console.log()
}

async function resetUser(supabase: ReturnType<typeof createServiceClient>, wpp: string) {
  const { data: user } = await supabase.from('users').select('id').eq('wpp', wpp).maybeSingle()
  if (!user) {
    console.log(`${ANSI.dim}(nada a apagar)${ANSI.reset}\n`)
    return
  }
  await supabase.from('users').delete().eq('id', user.id)
  console.log(`${ANSI.yellow}🗑️  Usuário ${wpp} apagado.${ANSI.reset}\n`)
}

async function main() {
  header()

  const supabase = createServiceClient({
    url: env('SUPABASE_URL'),
    serviceRoleKey: env('SUPABASE_SERVICE_ROLE_KEY'),
  })
  const llm = new OpenRouterLLM({
    apiKey: env('OPENROUTER_API_KEY'),
    heliconeApiKey: process.env.HELICONE_API_KEY,
  })
  const provider = new ConsoleProvider({ color: true })

  let currentWpp = '5511999999999'
  console.log(`${ANSI.dim}Conversando como ${currentWpp}${ANSI.reset}\n`)

  const rl = readline.createInterface({ input, output })

  while (true) {
    let line: string
    try {
      line = (await rl.question(`${ANSI.bold}${ANSI.green}você > ${ANSI.reset}`)).trim()
    } catch {
      break
    }
    if (!line) continue

    if (line === '/quit' || line === '/exit') break
    if (line === '/status') {
      await showStatus(supabase, currentWpp)
      continue
    }
    if (line === '/reset') {
      await resetUser(supabase, currentWpp)
      continue
    }
    if (line.startsWith('/from ')) {
      currentWpp = line.slice(6).trim()
      console.log(`${ANSI.dim}Agora conversando como ${currentWpp}${ANSI.reset}\n`)
      continue
    }

    try {
      const result = await processMessage(
        { supabase, llm },
        {
          from: currentWpp,
          providerMessageId: `cli_${Date.now()}`,
          text: line,
          contentType: 'text',
          provider: 'console',
          timestamp: new Date(),
        },
      )

      // Envio simulado via ConsoleProvider
      await provider.sendText(currentWpp, result.text)

      // Resumo abaixo da resposta
      const cost = result.costUsd != null ? `$${result.costUsd.toFixed(5)}` : '(?)'
      const tools = result.toolCalls.length
        ? ` | tools=${result.toolCalls.map((t) => t.name).join(',')}`
        : ''
      console.log(
        `${ANSI.dim}    [stage=${result.stage} model=${result.modelUsed} tokens=${result.promptTokens}+${result.completionTokens} ${cost} ${result.latencyMs}ms${tools}]${ANSI.reset}\n`,
      )
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e)
      console.error(`${ANSI.red}❌ erro: ${msg}${ANSI.reset}\n`)
    }
  }

  rl.close()
  console.log(`${ANSI.cyan}Tchau.${ANSI.reset}`)
}

main().catch((e) => {
  console.error('💥', e)
  process.exit(1)
})
