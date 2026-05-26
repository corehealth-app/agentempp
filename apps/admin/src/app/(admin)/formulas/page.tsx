import { ContentCard, PageHeader } from '@/components/page-header'
import { createServiceClient } from '@/lib/supabase/server'
import { CalcField } from '../settings/calc/form'

export const dynamic = 'force-dynamic'

interface ConfigItem {
  key: string
  value: unknown
  description: string | null
}

// Cada fórmula: equação por extenso + explicação + chaves de config (calc.*)
// editáveis ali mesmo. A ESTRUTURA da conta é código (travada por teste,
// docs/CALCULO-MPP.md) — aqui ela é DEMONSTRADA; os NÚMEROS são editáveis.
interface FormulaSection {
  id: string
  title: string
  equation: string[]
  explanation: string
  keys: string[]
  note?: string
}

const SECTIONS: FormulaSection[] = [
  {
    id: 'meta',
    title: 'Meta calórica diária',
    equation: [
      'Recomposição:  meta = BMR × 1,2 − déficit',
      'Ganho de massa: meta = BMR × fator_atividade × 1,05',
      'Manutenção:    meta = BMR × fator_atividade',
    ],
    explanation:
      'A meta de ingestão do dia. Na recomposição o exercício NÃO entra na meta (o TDEE é só informativo). O déficit varia pela fome do paciente.',
    keys: ['calc.recomp_bmr_multiplier', 'calc.ganho_massa_surplus_multiplier', 'calc.deficit_by_hunger'],
  },
  {
    id: 'bmr',
    title: 'BMR — metabolismo basal',
    equation: [
      'Mifflin-St Jeor (sem %BF): 10×peso + 6,25×altura − 5×idade + offset',
      '   offset: homem +5 · mulher −161',
      'Katch-McArdle (com %BF):   370 + 21,6 × massa magra',
    ],
    explanation:
      'Gasto de repouso. Usa Katch-McArdle quando há %BF (mais preciso); senão Mifflin-St Jeor.',
    keys: ['calc.bmr_mifflin', 'calc.bmr_katch'],
  },
  {
    id: 'tdee',
    title: 'TDEE — gasto total / fator de atividade',
    equation: ['TDEE = BMR × fator_atividade'],
    explanation:
      'Multiplicador do BMR pela rotina: sedentário 1,2 · leve 1,375 · moderado 1,55 · alto 1,725 · atleta 1,9.',
    keys: ['calc.activity_factors'],
  },
  {
    id: 'proteina',
    title: 'Meta de proteína',
    equation: ['meta_proteína (g) = fator × peso (kg)'],
    explanation:
      'Fator de proteína por g/kg, em cascata por fome + treino. Hoje todos em 1,5 (override do Dr. Roberto).',
    keys: ['calc.protein_factors'],
  },
  {
    id: 'balanco-comida',
    title: 'Balanço de comida — "Restam / Excedente" (card)',
    equation: ['balanço_comida = consumido − meta', '   < 0 → 🎯 Restam   ·   > 0 → 🎯 Excedente'],
    explanation:
      'O que o paciente vê no card. O EXERCÍCIO NÃO ENTRA aqui — queimar no treino NÃO libera comer mais. Esta é regra de código (não tem número editável).',
    keys: [],
    note: 'Regra fixa (código + teste). Mudança só via deploy.',
  },
  {
    id: 'balanco-net',
    title: 'Balanço do dia (déficit que alimenta o bloco)',
    equation: ['daily_balance = consumido − meta − exercício'],
    explanation:
      'O exercício CONTA aqui (vira déficit que acelera a perda). É o número que o fechamento do dia usa pra creditar o bloco 7700. Coluna gerada pelo banco.',
    keys: [],
    note: 'Regra fixa (código + coluna gerada). "Comida = sem exercício; bloco = com exercício."',
  },
  {
    id: 'bloco',
    title: 'Bloco 7700',
    equation: [
      '1 bloco = 7.700 kcal (≈ 1 kg de gordura)',
      'crédito do dia = máx(0, déficit_programado − daily_balance)',
      'bloco = soma(créditos) mod 7.700   ·   blocos = soma ÷ 7.700',
    ],
    explanation:
      'Acumula o déficit creditado por dia. Regras de integridade (código): sem atividade → 0; sub-registro (<50% da meta) → crédito reduzido; "pulei" → crédito normal; dia completo ≥50% → déficit programado + observado.',
    keys: ['calc.kcal_block'],
    note: 'A regra de crédito é código (travada por teste). Só o valor do bloco (7.700) é editável.',
  },
  {
    id: 'escadas',
    title: 'Escadas de meta (IMC / %BF) e elegibilidade',
    equation: [
      'IMC: próxima meta na escada [30, 25, 23, 22, 21] (margem mín. 1)',
      '%BF: >30 → bf−10 · >20 → 20 · >18 → 18 · >15 → 15 · base → 10',
      'Ganho exige: BF/IMC abaixo do limite + treino ≥ N/sem + sono ≥ Xh',
    ],
    explanation:
      'Metas progressivas de composição corporal e os critérios que decidem recomposição vs ganho de massa.',
    keys: ['calc.imc_goal_steps', 'calc.bf_goal_rules', 'calc.imc_limit_recomp', 'calc.bf_limits', 'calc.training_min', 'calc.sleep_min_hours'],
  },
  {
    id: 'gamificacao',
    title: 'Gamificação (XP, níveis, badges)',
    equation: ['nível por faixa de XP (8 níveis) · XP por ação · badges por meta'],
    explanation: 'Pontos por refeição/treino/proteína/etc., níveis por XP acumulado e badges.',
    keys: ['calc.levels', 'calc.xp_rules', 'calc.badges'],
  },
]

function num(map: Map<string, ConfigItem>, key: string, path?: string): number | null {
  const it = map.get(key)
  if (!it) return null
  if (path == null) return typeof it.value === 'number' ? it.value : null
  const v = (it.value as Record<string, unknown> | null)?.[path]
  return typeof v === 'number' ? v : null
}

export default async function FormulasPage() {
  const svc = createServiceClient()
  const { data: rows } = await (svc as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        like: (c: string, v: string) => { order: (c: string) => Promise<{ data: ConfigItem[] | null }> }
      }
    }
  })
    .from('global_config')
    .select('key, value, description')
    .like('key', 'calc.%')
    .order('key')

  const items = rows ?? []
  const map = new Map(items.map((i) => [i.key, i]))

  // Exemplo AO VIVO com os parâmetros atuais (ilustrativo): paciente 70kg, 170cm,
  // 30 anos, homem, sedentário, fome moderada, recomposição.
  const m = num(map, 'calc.bmr_mifflin', 'weight_coef') ?? 10
  const h = num(map, 'calc.bmr_mifflin', 'height_coef') ?? 6.25
  const a = num(map, 'calc.bmr_mifflin', 'age_coef') ?? 5
  const mo = num(map, 'calc.bmr_mifflin', 'male_offset') ?? 5
  const recompMult = num(map, 'calc.recomp_bmr_multiplier') ?? 1.2
  const defMod = num(map, 'calc.deficit_by_hunger', 'moderada') ?? 500
  const exBmr = m * 70 + h * 170 - a * 30 + mo
  const exMeta = Math.round(exBmr * recompMult - defMod)

  return (
    <div className="space-y-4">
      <PageHeader
        breadcrumbs={[{ label: 'Configuração' }, { label: 'Fórmulas' }]}
        title="Fórmulas do método MPP"
        description="Como o agente calcula tudo — demonstrado por extenso, com os números editáveis aqui mesmo. A estrutura da conta é código (travada por teste); os parâmetros (números) você ajusta aqui."
      />

      <div className="glass-card border-l-4 border-l-emerald-500/60 p-4 text-xs space-y-1">
        <p className="font-medium text-emerald-700 uppercase tracking-widest text-[10px]">
          🧮 Exemplo ao vivo (parâmetros atuais)
        </p>
        <p className="text-muted-foreground">
          Paciente exemplo: 70 kg · 170 cm · 30 anos · homem · sedentário · fome moderada ·
          recomposição.
        </p>
        <p className="font-mono text-[12px] text-foreground">
          BMR = {m}×70 + {h}×170 − {a}×30 + {mo} = <b>{exBmr.toLocaleString('pt-BR')}</b> kcal &nbsp;→&nbsp;
          Meta = {exBmr.toLocaleString('pt-BR')} × {recompMult} − {defMod} = <b>{exMeta.toLocaleString('pt-BR')}</b> kcal/dia
        </p>
      </div>

      <div className="glass-card border-l-4 border-l-amber-500/60 p-4 text-xs space-y-1">
        <p className="font-medium text-amber-700 uppercase tracking-widest text-[10px]">
          ⚠️ Mudar um número afeta TODOS os pacientes em tempo real
        </p>
        <p className="text-muted-foreground">
          Alterações aqui valem para novos cálculos em até ~1 min (sem deploy) e são registradas em
          auditoria. A <b>estrutura</b> das fórmulas (a forma da conta) é código travado por teste —
          mudar isso exige desenvolvimento + deploy. Fonte de verdade:{' '}
          <code className="font-mono bg-muted px-1 py-0.5 rounded">docs/CALCULO-MPP.md</code>.
        </p>
      </div>

      {SECTIONS.map((sec) => (
        <ContentCard key={sec.id} title={sec.title}>
          <div className="space-y-3">
            <pre className="text-[12px] font-mono whitespace-pre-wrap leading-relaxed bg-muted/50 rounded-md p-3 border border-border">
              {sec.equation.join('\n')}
            </pre>
            <p className="text-xs text-muted-foreground">{sec.explanation}</p>
            {sec.note && (
              <p className="text-[11px] text-amber-700/90 italic">🔒 {sec.note}</p>
            )}
            {sec.keys.length > 0 && (
              <div className="space-y-3 pt-1">
                <p className="text-[10px] uppercase tracking-widest text-muted-foreground font-medium">
                  Parâmetros editáveis
                </p>
                {sec.keys.map((k) => {
                  const item = map.get(k)
                  if (!item) return null
                  return <CalcField key={k} item={item} />
                })}
              </div>
            )}
          </div>
        </ContentCard>
      ))}
    </div>
  )
}
