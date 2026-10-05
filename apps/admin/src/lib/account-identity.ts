/**
 * Como o painel identifica uma conta na linha de contato.
 *
 * Toda conta do app Performe AI existe sem número de telefone (`wpp` nulo):
 * o número só existe nas contas antigas do canal de WhatsApp, encerrado.
 * Onde antes saía "+{wpp}", agora sai, nesta ordem: o número legado, o
 * e-mail (quando a tela já o carrega) ou "conta do app".
 */
export const APP_ACCOUNT_LABEL = 'conta do app'

export interface AccountContactSource {
  wpp?: string | null
  email?: string | null
}

export function accountContact(account: AccountContactSource): string {
  const wpp = account.wpp?.trim()
  if (wpp) return `+${wpp}`
  const email = account.email?.trim()
  if (email) return email
  return APP_ACCOUNT_LABEL
}

/** Nome de exibição: o nome, senão o contato (nunca vazio). */
export function accountDisplayName(account: AccountContactSource & { name?: string | null }) {
  const name = account.name?.trim()
  return name || accountContact(account)
}
