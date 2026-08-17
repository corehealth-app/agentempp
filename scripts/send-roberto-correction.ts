/**
 * ONE-OFF: envia a correção do bloco pro Roberto via endpoint admin de produção.
 * URL confirmada pelo Eduardo (2026-05-25): admin.corehealth.app.
 * Auth: Bearer SUPABASE_SERVICE_ROLE_KEY (lido do .env.local).
 * Pode apagar depois de enviar.
 */
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

function loadEnv(): Record<string, string> {
  const raw = readFileSync(resolve(process.cwd(), '../.env.local'), 'utf8')
  const out: Record<string, string> = {}
  for (const line of raw.split('\n')) {
    const m = line.match(/^([A-Z_]+)=(.*)$/)
    if (m && m[1] && m[2] !== undefined) out[m[1]] = m[2].replace(/^["']|["']$/g, '')
  }
  return out
}

const ADMIN_URL = 'https://admin.corehealth.app'
const ROBERTO_ID = '118587e3-e752-4a23-b304-57231d7ef40f'
const TEXT =
  'Roberto, corrigindo o card de mais cedo: seu saldo no bloco de 7.700 está em *1.235 kcal (16%)*, não 2.958. ' +
  'O fechamento de ontem (+479) está certo — 756 + 479 = 1.235, exatamente como você apontou. ' +
  'Foi erro só na exibição da mensagem; no sistema o valor sempre esteve correto.'

async function main() {
  const env = loadEnv()
  const key = env.SUPABASE_SERVICE_ROLE_KEY
  if (!key) throw new Error('SUPABASE_SERVICE_ROLE_KEY não achado no .env.local')

  const res = await fetch(`${ADMIN_URL}/api/admin/send-message`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ user_id: ROBERTO_ID, text: TEXT }),
  })
  const json = await res.json().catch(() => null)
  console.log('HTTP', res.status)
  console.log('resposta:', JSON.stringify(json, null, 2))
}

main().catch((e) => {
  console.error('ERRO:', e?.message ?? e)
  process.exit(1)
})
