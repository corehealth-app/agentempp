/**
 * Badge compacto pra mostrar país do paciente.
 * Diferencia "confirmado pelo paciente" vs "só palpite pelo DDI".
 */
import { cn } from '@/lib/utils'

const FLAGS: Record<string, string> = {
  BR: '🇧🇷',
  PT: '🇵🇹',
  ES: '🇪🇸',
  US: '🇺🇸',
  AR: '🇦🇷',
  MX: '🇲🇽',
  CL: '🇨🇱',
  CO: '🇨🇴',
  PE: '🇵🇪',
  UY: '🇺🇾',
  PY: '🇵🇾',
  BO: '🇧🇴',
  EC: '🇪🇨',
  VE: '🇻🇪',
  GB: '🇬🇧',
  DE: '🇩🇪',
  FR: '🇫🇷',
  IT: '🇮🇹',
  NL: '🇳🇱',
  CH: '🇨🇭',
  AT: '🇦🇹',
  IE: '🇮🇪',
  JP: '🇯🇵',
  KR: '🇰🇷',
  CN: '🇨🇳',
  IN: '🇮🇳',
  AU: '🇦🇺',
  CA: '🇨🇦',
}

export function CountryBadge({
  country,
  confirmed,
  size = 'md',
}: {
  country: string | null
  confirmed: boolean
  size?: 'sm' | 'md'
}) {
  if (!country) return null
  const flag = FLAGS[country] ?? '🌐'
  const isBR = country === 'BR'

  return (
    <span
      title={
        confirmed
          ? `País confirmado pelo usuário: ${country}`
          : `País ainda não confirmado pelo usuário: ${country}`
      }
      className={cn(
        'inline-flex items-center gap-1 font-mono uppercase tracking-widest rounded',
        size === 'sm' ? 'text-[9px] px-1 py-0' : 'text-[10px] px-1.5 py-0.5',
        confirmed
          ? isBR
            ? 'bg-moss-100 text-moss-700'
            : 'bg-amber-100 text-amber-800'
          : 'bg-muted text-muted-foreground/80 border border-dashed border-muted-foreground/30',
      )}
    >
      <span aria-hidden>{flag}</span>
      {country}
      {!confirmed && <span className="opacity-60">?</span>}
    </span>
  )
}
