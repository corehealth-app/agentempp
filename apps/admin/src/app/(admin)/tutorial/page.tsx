import Link from 'next/link'
import {
  Activity,
  AlertTriangle,
  ArrowRight,
  Bot,
  Calculator,
  Clock,
  Cpu,
  CreditCard,
  Eye,
  FileText,
  Flame,
  Globe,
  Key,
  Lightbulb,
  MessageSquare,
  RefreshCw,
  Rocket,
  RotateCcw,
  Search,
  Settings,
  Sparkles,
  Trash2,
  UserCog,
  Users,
  Wrench,
} from 'lucide-react'
import { ContentCard, PageHeader } from '@/components/page-header'

export default function TutorialPage() {
  return (
    <div className="space-y-6 max-w-4xl">
      <PageHeader
        breadcrumbs={[{ label: 'Tutorial' }]}
        title="O que dá pra mexer"
        description="Mapa completo de tudo que é editável via UI. Mudanças propagam em ≤1min sem deploy de código."
      />

      <ContentCard
        title="Filosofia"
        description="Tudo que afeta comportamento do agente em produção é editável aqui."
      >
        <div className="text-sm text-foreground/80 space-y-2 leading-relaxed">
          <p>
            A plataforma foi construída com a regra: <strong>nenhuma decisão clínica,
            nutricional, gamificação, agendamento ou conversa fica trancada em código</strong>.
            Cada constante mora em <Code>global_config</Code>, <Code>agent_configs</Code>,{' '}
            <Code>agent_rules</Code> ou em tabelas de configuração equivalentes.
          </p>
          <p>
            Os workers (Inngest functions) cacheiam config por 60s — então qualquer ajuste que
            você fizer aqui aparece em produção em ≤1min sem precisar de redeploy. Toda mudança
            grava <Code>audit_log</Code> automaticamente (quem, quando, o quê, antes/depois).
          </p>
          <p className="text-xs text-muted-foreground italic pt-1">
            Convenção visual: <Code>códigos assim</Code> são caminhos / nomes técnicos.
            Itens marcados ⚠️ requerem cuidado (impacto clínico ou irreversível).
          </p>
        </div>
      </ContentCard>

      {/* ====================================================== */}
      {/* QUICKSTART — primeira semana                            */}
      {/* ====================================================== */}
      <Section
        icon={Rocket}
        title="Primeira semana — quickstart"
        description="O que olhar e configurar nos primeiros dias antes de operar de verdade."
      >
        <div className="content-card p-5 space-y-3 text-sm">
          <Step n={1} title="Confirme as integrações">
            <Link href="/settings/api-keys" className="underline hover:text-moss-700">
              /settings/api-keys
            </Link>{' '}
            → todos os providers ativos (OpenRouter, ElevenLabs, WhatsApp Cloud, Stripe, Inngest).
            Use o botão <strong>Testar</strong> em cada um pra validar.
          </Step>
          <Step n={2} title="Verifique status do WhatsApp">
            Topbar mostra <Code>WHATSAPP GREEN · tier TIER_1K</Code>. Se aparecer YELLOW/RED ou
            tier baixo, sua conta Meta tá com quality rating ruim — pacientes não recebem.
          </Step>
          <Step n={3} title="Calibre os crons">
            <Link href="/settings/crons" className="underline hover:text-moss-700">
              /settings/crons
            </Link>{' '}
            → 12 jobs ativos. Os <Code>engagement-*</Code> disparam 5×/dia (heartbeats — sender
            escolhe slot por hora local). <Code>daily-closer-*</Code> roda 4× pra cobrir
            timezones. Editar schedule = clique em <strong>Editar</strong>, salvar.
          </Step>
          <Step n={4} title="Revise as regras críticas">
            <Link href="/prompts" className="underline hover:text-moss-700">
              /prompts
            </Link>{' '}
            → 88 regras. Filtra por categoria <Code>persona</Code>,{' '}
            <Code>tom_de_voz</Code>, <Code>tools</Code>. Editar usa diff viewer — antes de
            publicar você vê o que muda.
          </Step>
          <Step n={5} title="Faça uma conversa-teste">
            Manda &quot;oi&quot; pelo WhatsApp do bot pra abrir a janela 24h e testa o fluxo
            completo de onboarding. Acompanha em{' '}
            <Link href="/messages" className="underline hover:text-moss-700">
              /messages
            </Link>
            .
          </Step>
          <Step n={6} title="Configure alertas">
            <Link href="/settings/global" className="underline hover:text-moss-700">
              /settings/global
            </Link>{' '}
            → grupo <Code>alerts</Code>. Defina threshold de custo 24h e latência P95 pra ser
            avisado quando algo sair do esperado.
          </Step>
        </div>
      </Section>

      {/* ====================================================== */}
      {/* OPERAÇÃO                                                */}
      {/* ====================================================== */}
      <Section
        icon={Eye}
        title="Operação do dia-a-dia"
        description="Coisas que você toca em cada paciente individualmente."
      >
        <Item
          icon={MessageSquare}
          href="/messages"
          title="Conversas"
          description="Observatório do agente em tempo real. Lista lateral de pacientes (filtros: live, flag, pausa, silêncio) + thread central + sidebar com identidade/tags/notas/métricas."
          examples={[
            '⌘ K abre busca semântica em conversas (ex: "almocei pão", "ansiedade")',
            'Hover em msg OUT → 3 botões: 🚩 Flag (alucinação/boa/tom errado/etc), 🔄 Reprocessar (re-dispara o agente), ✏️ Fork pra Playground',
            'Hover em msg IN → 🔄 Reprocessar (re-dispara processamento)',
            'Sidebar direita → Pausar agente (1-60d), editar nome/notas, adicionar tags',
          ]}
        />
        <Item
          icon={Users}
          href="/users"
          title="Pacientes"
          description="Lista de todos com país detectado/confirmado, plano, status. Click abre /users/[id]."
          examples={[
            'Filtra "sem nome" → identifica testes vs onboarding incompleto',
            'Click no paciente → vê BMR, IMC, protocolo, snapshots 14d, conversas, assinatura',
          ]}
        />
        <SubItem
          icon={Globe}
          title="Confirmar país manualmente"
          description="Quando o LLM não chama confirma_pais_residencia mesmo o paciente respondendo. /users/[id] → header tem botão âmbar 'Confirmar país' (só aparece se country_confirmed=false). Pode trocar o ISO antes de confirmar."
        />
        <SubItem
          icon={Globe}
          title="Idioma e sistema de medidas (por paciente)"
          description="O agente NÃO assume idioma/unidade só por país. Brasileiro nos EUA pode preferir PT; americano pode usar lb/inch. Tool confirma_pais_residencia recebe 3 args (country, language, unit_system) e a regra obriga perguntar quando country!=BR ou imperial. Se paciente pedir trocar de idioma no meio da conversa, agente muda na hora e re-chama a tool pra persistir. users.locale + users.metadata.unit_system guardam o estado."
        />
        <SubItem
          icon={CreditCard}
          title="Gerar link de checkout Stripe"
          description="/users/[id] → seção Assinatura → botões 'Mensal R$197' / 'Anual R$1.164'. Cria sessão Stripe e devolve URL pra você mandar manual ao paciente (link válido 24h)."
        />
        <SubItem
          icon={RotateCcw}
          title="Resetar conversa"
          description="⚠️ Apaga TODAS mensagens, refeições, treinos, snapshots, progresso, embeddings. Mantém o paciente cadastrado mas zera onboarding (nome, perfil, badges). Mantém subscription Stripe ativa. Confirmação textual obrigatória ('RESETAR')."
        />
        <SubItem
          icon={Trash2}
          title="Excluir paciente"
          description="⚠️ CASCADE total: apaga user + tudo relacionado (FK ON DELETE CASCADE). Próxima msg dele no WhatsApp será tratada como paciente novo (1ª interação). Confirmação textual obrigatória ('EXCLUIR')."
        />
      </Section>

      {/* ====================================================== */}
      {/* CURADORIA                                               */}
      {/* ====================================================== */}
      <Section
        icon={Sparkles}
        title="Curadoria do agente"
        description="Como o agente fala, decide, usa tools e qual modelo roda em cada estágio."
      >
        <Item
          icon={FileText}
          href="/prompts"
          title="Regras (88+) e system prompts"
          description="Editor com diff viewer e versionamento. Cada regra tem categoria, prioridade, ativa/inativa. System prompt de cada estágio tem sua própria versão em agent_rules_versions."
          examples={[
            'Mudar voz/tom → editar regra de persona, "Salvar como rascunho", "Publicar"',
            'Comparar com versão anterior → diff viewer side-by-side, vermelho=removido verde=adicionado',
            'Despublicar regra problemática → toggle ativa=false (mantém histórico)',
            'Reverter → escolher versão anterior em agent_rules_versions, "Restaurar essa"',
          ]}
        />
        <Item
          icon={Bot}
          href="/prompts/playground"
          title="Playground"
          description="Testa prompt ad-hoc sem afetar produção. Pode usar seed real (paste msg do WhatsApp) ou texto livre. Mostra cost USD, tokens, latency. Se ficou bom, copia pro prompt do estágio."
        />
        <Item
          icon={Cpu}
          href="/settings/agents"
          title="Sub-agentes (modelo + temperatura + tokens)"
          description="6 estágios distintos. Cada um pode rodar em modelo diferente (custo vs qualidade). Versionado em agent_configs_versions."
          examples={[
            'coleta_dados — onboarding inicial, faz perguntas estruturadas pra preencher perfil',
            'recomposicao / ganho_massa / manutencao — protocolos por objetivo, fala diferente em cada',
            'analista_diario (cron 03h) — gera resumo do dia anterior',
            'engajamento (cron 5×/dia) — proatividade fora de conversa',
            '⚠️ Trocar modelo afeta custo + qualidade — teste no playground antes',
          ]}
        />
        <Item
          icon={Sparkles}
          href="/evaluations"
          title="Avaliações LLM"
          description="LLM-as-judge avalia conversas das últimas 50 msgs. Score 0-10 + justificativa. Distribuição alta (≥8) / média (6-8) / baixa (<6). Use pra decidir o que melhorar nas regras."
        />
        <Item
          icon={Wrench}
          href="/settings/tools"
          title="Tools (capabilities do agente)"
          description="Lista todas as tools que o LLM pode chamar (registra_refeicao, registra_treino, consulta_metricas, confirma_pais_residencia, etc) com description completa + parâmetros + em quais stages cada uma está habilitada. Description = instrução de QUANDO usar (vai pro modelo no system prompt). Editar exige código + deploy. Ligar/desligar por stage: /settings/agents → allowed_tools."
          examples={[
            'Ver registra_refeicao description (cláusulas anti-bug "padrão alimentar não é refeição")',
            'Confirmar que consulta_metricas está habilitada nos stages de protocolo',
            'Ver schema dos parâmetros (food_name, quantity_g, meal_type, etc)',
          ]}
        />
        <Item
          icon={FileText}
          href="/prompts?tipo=regras_gerais"
          title="Vision · 5 prompts (meal/body/scale/other/classifier)"
          description="Como o modelo lê fotos. Editáveis em /prompts (slug começa com 'vision-'). Cache 60s — mudança propaga ≤1min sem deploy."
          examples={[
            'vision-classifier — escolhe meal/body/scale/other antes de analisar',
            'vision-meal — chain-of-thought 4 passos: identifica → nomeia PT-BR → estima quantidade → auto-checa confidence',
            'vision-body — estima BF% por ângulo + composição visível',
            'vision-scale — lê número da balança e converte lb→kg',
            'vision-other — fallback descritivo pra fotos não-padrão',
            'Modelo + threshold de confidence editáveis em /settings/global (vision.* keys)',
          ]}
        />
      </Section>

      {/* ====================================================== */}
      {/* CÁLCULOS                                                */}
      {/* ====================================================== */}
      <Section
        icon={Calculator}
        title="Cálculos e parâmetros"
        description="Toda fórmula determinística (BMR, TDEE, IMC, badges, XP) e config runtime."
      >
        <Item
          icon={Calculator}
          href="/settings/calc"
          title="Constantes de cálculo (13)"
          description="⚠️ Impacto clínico — alterar coeficientes da BMR Mifflin-St Jeor afeta recomendações de calorias pra TODOS os pacientes."
          examples={[
            'BMR Mifflin: weight_coef, height_coef, age_coef, male_offset, female_offset',
            'BMR Katch-McArdle (com %BF): base, lbm_coef',
            'Activity factors: sedentario / leve / moderado / alto / atleta',
            'Protein factors: pouca / moderada / muita (g/kg corporal)',
            'KCAL_BLOCK = 7700 (1kg gordura)',
            'IMC limit recomp (25), training_min (3), BF limits por sexo',
            'Levels XP (7 níveis com nomes), badges (6 tipos), xp_rules diárias',
          ]}
        />
        <Item
          icon={Settings}
          href="/settings/global"
          title="Config global (32+ chaves em 9 grupos)"
          description="Tudo que não é por-paciente. Agrupado por prefixo do key:"
          groups={[
            { name: 'rate_limit', count: 2, what: 'Msgs/user/min, custo/user/dia' },
            { name: 'alerts', count: 3, what: 'Custo 24h, latência P95, taxa de erro de tools' },
            { name: 'tts', count: 5, what: 'ElevenLabs stability/similarity/speed/style + rewriter on/off' },
            { name: 'engagement', count: 5, what: 'Wake/bed offsets + fallbacks + slots (thresholds + meal_hints)' },
            { name: 'humanizer', count: 4, what: 'Velocidade de digitação simulada (chars/s, delays)' },
            { name: 'buffer', count: 1, what: 'Debounce do webhook WhatsApp (ms — agrega msgs próximas)' },
            { name: 'attention', count: 7, what: 'Thresholds das categorias do "Quem precisa da sua atenção"' },
            { name: 'calc', count: 13, what: 'Mesmas chaves de /settings/calc (UI dedicada)' },
            { name: 'country_to_language', count: 1, what: 'Map de país → idioma da persona' },
            { name: 'persona', count: 1, what: 'Variações de persona por país (Dr. Roberto / Robert)' },
            { name: 'vision', count: 2, what: 'Modelo OpenRouter (gemini-2.5-flash) + threshold de confidence pra flag ⚠️ INCERTO' },
          ]}
        />
        <Item
          icon={Calculator}
          href="/settings/foods"
          title="Banco de alimentos (food_db)"
          description="Base nutricional consultada quando o agente registra refeição. Vision identifica os itens, esta tabela fornece kcal/proteína/carb/gordura por 100g. Match por trigram em name_pt. Adicione novos quando vir '0 kcal sem match'."
          examples={[
            '~233 alimentos BR (TACO + 108 aliases populares)',
            'Adicionar regional: ex "tacacá" → kcal/protein/carb/fat por 100g',
            'Editar inline: nome, categoria, macros, fonte (alias / TACO / manual)',
            'Filtros: busca por nome, categoria, fonte',
            '⚠️ Nome deve ser PT-BR popular ("ovo frito"), NÃO técnico ("ovo de galinha mexido")',
          ]}
        />
      </Section>

      {/* ====================================================== */}
      {/* AUDITORIA AUTOMÁTICA                                    */}
      {/* ====================================================== */}
      <Section
        icon={Activity}
        title="Auditoria automática (routine remota)"
        description="Agente Claude rodando 3x/dia detecta bugs e aplica fixes simples sem intervenção manual."
      >
        <Item
          icon={Activity}
          href="/audit"
          title="Routine 3x/dia (08h, 14h, 20h BRT)"
          description="Routine Anthropic Cloud (id trig_01VWD1RPAi…). A cada execução: GET /functions/v1/audit-findings (agrega últimas 8h), classifica severidade e age."
          examples={[
            'Edge function audit-findings: agrega numeric_mismatches, meal_warnings, tools_failed, foods sem match repetido',
            'Edge function audit-auto-fix: aceita só food_alias com sanity dupla (kcal vs prot×4+carb×4+fat×9)',
            'Auto-fixes aparecem em /audit (card verde) com source=alias_auto, revertível em /settings/foods?source=alias_auto',
            'Bugs estruturais (alucinações, races, prompt drifts) são reportados na resposta da routine — investigação manual',
            'Cron expression: 0 11,17,23 * * * (UTC)',
            'Limites: NUNCA mexe em código, NUNCA deleta dado, aborta se findings >50 (anormal)',
          ]}
        />
      </Section>

      {/* ====================================================== */}
      {/* CRONS                                                   */}
      {/* ====================================================== */}
      <Section
        icon={Clock}
        title="Crons e automação"
        description="Agendamentos rodando via pg_cron + Inngest workers."
      >
        <Item
          icon={Clock}
          href="/settings/crons"
          title="Cron jobs (12)"
          description="Cada job tem 3 ações inline com optimistic UI: Editar (cron expression 5/6 campos), Ativar/Desativar (toggle pg_cron), Rodar agora (executa o command imediatamente, fora do schedule). Toda mudança vai pro audit_log."
          examples={[
            'engagement-* (5×/dia) — heartbeats, sender escolhe slot por hora local',
            'daily-closer-* (4 horários: 00h30, 01h30, 02h30, 03h30 UTC) — cobre múltiplos timezones',
            'cleanup-processed-messages (04h diário) — DELETE messages > 30d',
            'wa-quality-check (30min) — monitora quality rating do WhatsApp Business',
            'refresh-mv-kpis-daily (1×/dia) — recomputa materialized view dos KPIs',
          ]}
        />
      </Section>

      {/* ====================================================== */}
      {/* INTEGRAÇÕES                                             */}
      {/* ====================================================== */}
      <Section
        icon={Key}
        title="Integrações"
        description="Credentials de providers externos — todos editáveis."
      >
        <Item
          icon={Key}
          href="/settings/api-keys"
          title="API Keys (8 providers)"
          description="OpenRouter, Groq, ElevenLabs (×2 voices), WhatsApp Cloud API (Meta), Stripe, Inngest, Sentry. Cada um com botão 'Testar' que valida sem aplicar."
          examples={[
            'OpenRouter api_key — usado por todos os modelos LLM',
            'WhatsApp: phone_number_id, waba_id, access_token, verify_token, app_secret',
            'Stripe: secret_key, publishable_key, webhook_secret',
            '⚠️ Trocar key invalida tokens em uso — fluxos em andamento podem falhar 1×',
          ]}
        />
        <Item
          icon={CreditCard}
          href="/settings/stripe"
          title="Stripe — produtos + sync"
          description="Sincroniza produtos do Stripe (lookup_keys mpp_mensal_v1, mpp_anual_v1) com a DB local. Edita preço/nome no Stripe Dashboard, vem aqui e clica Sync."
        />
      </Section>

      {/* ====================================================== */}
      {/* GOVERNANÇA                                              */}
      {/* ====================================================== */}
      <Section
        icon={Activity}
        title="Governança e atenção"
        description="O que olhar pra saber se algo precisa intervenção manual."
      >
        <Item
          icon={AlertTriangle}
          href="/dashboard"
          title='"Quem precisa da sua atenção"'
          description="Feed automático no topo do dashboard — top 5 ordenados por prioridade."
          examples={[
            '🚨 error_recent (priority 9) — tool falhou nas últimas 6h',
            '💸 payment_failed (8) — subscription past_due/canceled/expired últimos 7d',
            '⏳ onboarding_stuck (7) — incompleto >24h, paciente cadastrado <14d',
            '😴 silent_user (5) — sem msg IN há 3-14 dias (depois disso = churned)',
            '🏆 block_milestone (3) — fechou bloco 7700 nas últimas 24h',
            'Cada card tem botões inline: Conversa / Adiar 24h / Resolver',
          ]}
        />
        <Item
          icon={Activity}
          href="/audit"
          title="Auditoria"
          description="Feed de todas as ações administrativas: quem editou regra, quem reset paciente, quem mudou cron, quem confirmou país, attention.snooze/dismiss, etc. 200 últimas, ordenadas por data."
        />
        <Item
          icon={UserCog}
          href="/settings/admins"
          title="Admins"
          description="CRUD de quem tem acesso ao painel. Adiciona email + role. RLS bloqueia tudo fora de admin_users — login normal não passa do /login se email não estiver cadastrado."
        />
      </Section>

      {/* ====================================================== */}
      {/* FAQ / TROUBLESHOOTING                                   */}
      {/* ====================================================== */}
      <Section
        icon={Wrench}
        title="Troubleshooting — problemas comuns"
        description="Sintomas que aparecem no dia a dia e onde olhar."
      >
        <Faq
          q="Paciente não recebe mensagens no WhatsApp"
          a={[
            'Olhar /users/[id] → Conversas recentes → última msg OUT tem delivery_status?',
            '"sent" + null delivery_error → Meta API aceitou mas pode estar fora da janela 24h.',
            'WhatsApp Cloud API só entrega texto livre se o paciente mandou msg pras últimas 24h.',
            'Solução imediata: pede pro paciente mandar qualquer "oi" — abre janela.',
            'Solução estrutural: implementar Message Templates aprovados Meta (fora da janela só template funciona).',
          ]}
        />
        <Faq
          q="Agente fica em loop perguntando a mesma coisa"
          a={[
            'Provável: tool não foi chamada quando o paciente respondeu.',
            'Caso clássico: country_confirmed=false. Vai em /users/[id] → botão "Confirmar país".',
            'Outras tools: olhar /audit filtrando por tools_audit pra ver se tem falha.',
            'Se persistir: editar a regra de prompt pra ser mais explícita sobre quando chamar a tool.',
          ]}
        />
        <Faq
          q="Agente respondeu em inglês mesmo após paciente pedir português"
          a={[
            'A regra Persona master tem "REGRA DE IDIOMA (inviolável)": responde no idioma da última msg do paciente, não no locale salvo.',
            'Se o paciente pedir trocar ("fale em português"), agente muda na hora E chama confirma_pais_residencia pra persistir o language.',
            'Se ainda falhar: editar a regra Persona master em /prompts (slug persona-master-dr-roberto-amigo-coach) pra reforçar o idioma.',
            'O locale salvo do paciente fica em users.locale — pode editar direto via SQL como fallback.',
          ]}
        />
        <Faq
          q='Foto de prato volta com "0 kcal (sem match TACO)"'
          a={[
            'Vision identificou o item mas o nome não casou com nada no food_db (trigram threshold 0.3).',
            'Solução imediata: /settings/foods → adiciona o alimento com nome que a vision retornou + macros por 100g.',
            'Solução estrutural: melhorar o prompt vision-meal em /prompts pra usar nomes que JÁ existem no food_db.',
            'Vision retorna "ovo de galinha frito" mas TACO tem "ovo frito"? Adiciona alias no food_db ou ajusta prompt.',
          ]}
        />
        <Faq
          q="Vision identificou comida com confiança baixa, agente registrou direto"
          a={[
            'Threshold padrão é 0.6 (vision.meal.confidence_threshold em /settings/global).',
            'Itens abaixo dele recebem flag ⚠️ INCERTO no contexto e o agente DEVE perguntar antes de registrar.',
            'Se ele registrou mesmo assim: a regra do prompt do estágio precisa reforçar essa diretiva. Subir o threshold pra 0.75 também ajuda.',
            'Pra desabilitar a confirmação (volta ao registro automático): threshold = 0.',
          ]}
        />
        <Faq
          q="Múltiplas fotos enviadas em sequência mas agente leu só uma"
          a={[
            'Bug histórico: webhook fazia read-then-write no message_buffer → race entre 3 webhooks paralelos.',
            'Corrigido: RPC buffer_append_msg usa INSERT...ON CONFLICT DO UPDATE atômico (jsonb || jsonb).',
            'Se persistir: olhar /audit pra ver se as 3 entraram em messages, e o buffer agregou todas.',
          ]}
        />
        <Faq
          q="Cron de engajamento mandou meta diferente da que o agente disse em conversa"
          a={[
            'Era alucinação: engagement-sender não passava calories_target/protein_target reais pro LLM. Prompt tinha placeholders {meta_diaria_kcal} mas eles não eram substituídos. LLM com temp=1.2 inventava valor plausível.',
            'Corrigido: cron carrega loadDailyTargets() + daily_snapshots de hoje/ontem ANTES do LLM, e injeta no userContext com headline "USE ESTES VALORES, NÃO INVENTE".',
            'Defesa em camadas: pipeline.ts formatUserContext faz o mesmo pra TODA conversa (não só engagement). Persona master ganhou "REGRA INVIOLÁVEL" proibindo cálculo mental. Tool consulta_metricas como escape hatch.',
          ]}
        />
        <Faq
          q="Agente inventou número (BMR, TDEE, IMC, idade, streak) na resposta"
          a={[
            'Esse padrão é geral: LLM gera dado quantitativo crítico na cabeça em vez de usar fonte determinística.',
            'Mitigações ativas (defense-in-depth, 5 camadas):',
            '  1) formatUserContext em pipeline.ts injeta meta calórica, meta proteína, consumo do dia, balanço, déficit acumulado, streak, XP, level, blocos completos, IMC, BMR, TDEE, LBM, idade, fórmula usada (Mifflin/Katch).',
            '  2) Persona master tem "REGRA INVIOLÁVEL: Anti-alucinação numérica" (PT/EN/ES) com lista explícita do que NUNCA calcular.',
            '  3) Tool consulta_metricas retorna todos os valores determinísticos quando contexto está stale ou paciente pede algo não-injetado.',
            '  4) Validador de saída: pipeline.ts parseia números na resposta antes de enviar e compara com valor real. Divergência >10% vira evento llm.numeric_mismatch em product_events.',
            '  5) Temperature reduzida no engagement (1.2 → 0.85) — menos criatividade quando há números a entregar.',
            'Onde ver: /audit mostra alerta vermelho no topo se houve mismatch nas últimas 24h.',
            'Se ainda encontrar alucinação: copie o trecho exato em /messages → forke pra Playground com o contexto real e veja se o LLM repete; se sim, reforçar regra; se não, era stale data.',
          ]}
        />
        <Faq
          q="Custo IA disparou no dashboard"
          a={[
            'Topbar mostra "Custo 24h $X" — se subiu muito, /messages → filtra por modelo.',
            'Causas comuns: modelo trocado pra mais caro, paciente em loop com tool error, prompts muito longos.',
            'Mitigação: /settings/global → rate_limit.cost_per_user_per_day_usd (cap por user).',
            'Mitigação: /settings/agents → trocar modelo do estágio mais ativo (geralmente coleta_dados) pra Haiku/Groq.',
          ]}
        />
        <Faq
          q="Cron não rodou no horário esperado"
          a={[
            '/settings/crons → status do job: ATIVO ou INATIVO?',
            'Se ATIVO mas last_run vazio: cron falhou. Olhar /audit ou Inngest dashboard.',
            'Inngest pode estar no plano free atingiu limite — checar Inngest Cloud.',
            'Pra forçar agora: clica "Rodar agora" no card do cron.',
          ]}
        />
        <Faq
          q='"Quem precisa da sua atenção" não atualiza'
          a={[
            'View v_attention_items é recalculada a cada GET — não há cache.',
            'Se um item sumiu mas você esperava ele lá: thresholds em /settings/global → attention.* podem ter mudado.',
            'Item dismissed (Resolver) só volta se condição voltar a se aplicar (nova ocorrência).',
            'Pra reverter dismiss: SQL → DELETE FROM attention_dismissals WHERE user_id=X AND kind=Y.',
          ]}
        />
        <Faq
          q="Não consigo logar mesmo sendo admin"
          a={[
            'Confere /settings/admins — seu email tem que estar cadastrado.',
            'Login no Supabase Auth ≠ entrar no painel — tem RLS gate em admin_users.',
            'Se email tá na lista mas falha: cookie expirou. Logout e login novamente.',
          ]}
        />
        <Faq
          q="Tutorial menciona X mas não vejo a opção"
          a={[
            'Provável deploy desatualizado — Ctrl+Shift+R pra hard refresh.',
            'Versão deployada visível em /audit (último commit no rodapé).',
            'Algumas features dependem de Edge Function deployada (ex: buffer.debounce_ms só faz efeito se webhook-whatsapp foi redeployado pós migration).',
          ]}
        />
      </Section>

      {/* ====================================================== */}
      {/* GLOSSÁRIO                                               */}
      {/* ====================================================== */}
      <Section
        icon={Lightbulb}
        title="Glossário"
        description="Termos técnicos que aparecem no painel."
      >
        <div className="content-card p-5 space-y-3 text-sm">
          <Term word="Stage (estágio)">
            Cada paciente está em um de 6 estágios determinados pelo perfil:{' '}
            <Code>coleta_dados</Code> (onboarding) → <Code>recomposicao</Code> ou{' '}
            <Code>ganho_massa</Code> ou <Code>manutencao</Code> (protocolos). Crons usam{' '}
            <Code>analista_diario</Code> e <Code>engajamento</Code>. Cada stage tem seu próprio
            system prompt, modelo e config.
          </Term>
          <Term word="Bloco 7700">
            Unidade de gamificação. 1kg de gordura = 7700 kcal de déficit. Quando o paciente
            acumula 7700 kcal de déficit, fecha 1 bloco e ganha XP + badge. Editável em{' '}
            <Code>calc.kcal_block</Code>.
          </Term>
          <Term word="IMC / BF%">
            IMC = peso/(altura²) em kg/m². BF% = body fat percent (gordura corporal). O agente
            usa BF% se disponível (mais preciso pra Katch-McArdle); senão IMC pra rotear
            protocolo.
          </Term>
          <Term word="BMR / TDEE">
            BMR = basal metabolic rate (gasto em repouso). TDEE = total daily energy expenditure
            (BMR × fator de atividade). Base do cálculo de kcal alvo do paciente.
          </Term>
          <Term word="Janela 24h (WhatsApp)">
            Regra da Meta: agente só pode mandar texto livre dentro de 24h após paciente enviar
            uma msg. Fora da janela, só Message Templates aprovados pela Meta funcionam.
          </Term>
          <Term word="Buffer debounce">
            Quando paciente manda 3 msgs em sequência, o webhook agrega elas (8s default) antes
            de disparar o agente — economiza calls de LLM. Editável em{' '}
            <Code>buffer.debounce_ms</Code>.
          </Term>
          <Term word="Humanizer">
            Simula digitação humana: delay entre msgs OUT, &quot;digitando…&quot; visível no
            WhatsApp, velocidade proporcional ao tamanho do texto. Editável em{' '}
            <Code>humanizer.*</Code>.
          </Term>
          <Term word="Tier (WhatsApp)">
            Limite de pacientes únicos que sua conta WABA pode contatar/24h. TIER_1K = 1000.
            Sobe automaticamente conforme quality rating sustenta GREEN.
          </Term>
          <Term word="Quality rating (WhatsApp)">
            GREEN/YELLOW/RED. Calculado pela Meta com base em quem bloqueou/reportou. Cair pra
            RED → conta suspensa.
          </Term>
          <Term word="Slot de engajamento">
            Período do dia (cafe_da_manha, almoco, jantar, etc) derivado da hora local do
            paciente. Determina o tom da msg de engajamento. Editável em{' '}
            <Code>engagement.slots</Code>.
          </Term>
          <Term word="Reentry warm">
            Quando paciente volta após dias sem mandar msg, o agente recebe instrução especial
            no system prompt: &quot;cumprimentar de volta, fazer resumo curto, não recomeçar
            onboarding&quot;.
          </Term>
          <Term word="agent_rules_versions">
            Tabela de versionamento das 88 regras. Toda edição cria nova versão. Permite ver
            histórico e restaurar. Não há limite de versões.
          </Term>
        </div>
      </Section>

      {/* ====================================================== */}
      {/* OBSERVABILIDADE                                         */}
      {/* ====================================================== */}
      <ContentCard
        title="Onde olhar logs quando algo dá errado"
        description="Por camada da stack."
      >
        <div className="space-y-2 text-sm">
          <LogRow
            where="Vercel Functions"
            url="https://vercel.com/gestao-9664s-projects/agentempp/logs"
            what="API routes (/api/inngest, /api/stripe/*, /api/media/*) + erros do Next.js"
          />
          <LogRow
            where="Inngest Cloud"
            url="https://app.inngest.com"
            what="Workers (engagement-sender, daily-closer, process-message, buffer-listener) — cada step com input/output, retries, falhas"
          />
          <LogRow
            where="Supabase Logs"
            url="https://supabase.com/dashboard/project/xuxehkhdvjivitduarvb/logs"
            what="Edge Functions (webhook-whatsapp, webhook-stripe), Postgres queries, pg_cron history"
          />
          <LogRow
            where="Meta Business Suite"
            url="https://business.facebook.com"
            what="WhatsApp delivery rates, quality rating, template approvals, account restrictions"
          />
          <LogRow
            where="Stripe Dashboard"
            url="https://dashboard.stripe.com"
            what="Webhook deliveries (que disparam pra /webhook-stripe), failed payments, dispute events"
          />
        </div>
      </ContentCard>

      {/* ====================================================== */}
      {/* ATALHOS                                                 */}
      {/* ====================================================== */}
      <ContentCard title="Atalhos úteis" description="Coisas escondidas que economizam tempo.">
        <div className="space-y-2 text-sm">
          <ShortcutRow
            shortcut="⌘ K"
            label="Command palette"
            description="Busca conversas semanticamente, abre páginas rápido."
          />
          <ShortcutRow
            shortcut="/"
            label="Foco na busca de conversas"
            description="Em /messages, vai direto pro campo de busca."
          />
          <ShortcutRow
            shortcut="Hover"
            label="Tooltips em badges"
            description='País "BR ✓" → "confirmado pelo paciente"; "BR ?" → "detectado pelo DDI".'
          />
          <ShortcutRow
            shortcut="Hover msg"
            label="Ações em mensagens"
            description="OUT: 🚩 Flag, 🔄 Reprocessar, ✏️ Fork pro Playground. IN: 🔄 Reprocessar."
          />
          <ShortcutRow
            shortcut="Click outside"
            label="Cancelar edits"
            description="Edits inline (cron expression, nome do paciente, tags) cancelam ao clicar fora ou Esc."
          />
        </div>
      </ContentCard>

      {/* ====================================================== */}
      {/* ARQUITETURA                                             */}
      {/* ====================================================== */}
      <ContentCard title="Onde tudo mora" description="Mapa da stack — útil pra dev de manutenção.">
        <div className="text-sm text-foreground/80 space-y-2 leading-relaxed">
          <p>
            <strong>Frontend (Vercel)</strong>: <Code>apps/admin</Code> (Next.js 15) +{' '}
            <Code>/api/inngest</Code> servindo as funções workers. Auto-deploy não funciona —{' '}
            tem que rodar <Code>vercel --prod</Code> manual + alias.
          </p>
          <p>
            <strong>Backend (Supabase)</strong>: Postgres + RLS + pg_cron + 2 Edge Functions
            (webhook-whatsapp, webhook-stripe). Cada migration em{' '}
            <Code>supabase/migrations</Code>. Aplicar com <Code>supabase db push --linked</Code>.
          </p>
          <p>
            <strong>Workers (Inngest Cloud)</strong>: <Code>packages/inngest-functions</Code> —
            engagement-sender, daily-closer, process-message, buffer-listener, wa-quality-check.
            Servidos via <Code>/api/inngest</Code> da Vercel — redeploy de Vercel = redeploy de
            workers.
          </p>
          <p>
            <strong>Lógica pura testável</strong>: <Code>packages/core</Code> (BMR, IMC, blocos,
            XP, badges, protocolo) — 40+ tests cobrindo as fórmulas. Constantes default em{' '}
            <Code>calc-config.ts</Code> (DEFAULT_CALC_CONFIG); produção lê de{' '}
            <Code>global_config</Code>.
          </p>
          <p>
            <strong>Agente (LLM pipeline)</strong>: <Code>packages/agent</Code> — orquestração
            do LLM (escolha de modelo, system prompt, tool loop, persistência da OUT).
            Loaders com cache 60s pra config.
          </p>
        </div>
      </ContentCard>

      <ContentCard title="Próximas ideias">
        <div className="space-y-1.5 text-sm text-muted-foreground">
          <p>Coisas que poderiam ser adicionadas se forem prioridade:</p>
          <ul className="space-y-1 ml-4 list-disc">
            <li>Message Templates Meta — entregar engajamento fora da janela 24h</li>
            <li>Realtime na lista de conversas (websocket Supabase) — hoje precisa F5</li>
            <li>Bulk actions em /users (selecionar vários e tag em massa)</li>
            <li>Import/export de regras (.json) — backup/sharing entre instâncias</li>
            <li>A/B testing de prompts — split N% pra versão B, comparar evaluations</li>
          </ul>
        </div>
      </ContentCard>
    </div>
  )
}

// ============================================================================
// helpers
// ============================================================================

function Section({
  icon: Icon,
  title,
  description,
  children,
}: {
  icon?: React.ComponentType<{ className?: string }>
  title: string
  description: string
  children: React.ReactNode
}) {
  return (
    <div className="space-y-3">
      <div className="px-1 pt-2 flex items-start gap-2.5">
        {Icon && (
          <div className="shrink-0 mt-1 h-7 w-7 rounded-md bg-moss-700/10 text-moss-700 flex items-center justify-center">
            <Icon className="h-4 w-4" />
          </div>
        )}
        <div>
          <h2 className="font-display text-xl tracking-tight text-foreground">{title}</h2>
          <p className="text-sm text-muted-foreground mt-0.5">{description}</p>
        </div>
      </div>
      <div className="space-y-2">{children}</div>
    </div>
  )
}

function Item({
  icon: Icon,
  href,
  title,
  description,
  examples,
  groups,
}: {
  icon: React.ComponentType<{ className?: string }>
  href?: string
  title: string
  description: string
  examples?: string[]
  groups?: Array<{ name: string; count: number; what: string }>
}) {
  const inner = (
    <div className="content-card p-4 flex gap-3 hover:bg-muted/30 transition-colors">
      <div className="shrink-0 h-9 w-9 rounded-md bg-moss-700/10 text-moss-700 flex items-center justify-center">
        <Icon className="h-4 w-4" />
      </div>
      <div className="flex-1 min-w-0 space-y-1.5">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="font-medium text-foreground">{title}</span>
          {href && (
            <code className="font-mono text-[10px] bg-muted px-1.5 py-0.5 rounded text-muted-foreground">
              {href}
            </code>
          )}
        </div>
        <p className="text-sm text-muted-foreground leading-relaxed">{description}</p>
        {examples && (
          <ul className="text-xs text-foreground/70 space-y-0.5 mt-2">
            {examples.map((e, i) => (
              <li key={i} className="flex gap-2">
                <span className="text-moss-600 shrink-0">▸</span>
                <span>{e}</span>
              </li>
            ))}
          </ul>
        )}
        {groups && (
          <ul className="text-xs space-y-0.5 mt-2">
            {groups.map((g) => (
              <li key={g.name} className="flex gap-2 items-baseline">
                <code className="font-mono text-[11px] text-moss-700 shrink-0 min-w-[140px]">
                  {g.name}.* ({g.count})
                </code>
                <span className="text-muted-foreground">{g.what}</span>
              </li>
            ))}
          </ul>
        )}
      </div>
      {href && (
        <ArrowRight className="h-4 w-4 text-muted-foreground/40 mt-1 shrink-0 self-start" />
      )}
    </div>
  )
  if (href) {
    return (
      <Link href={href} className="block">
        {inner}
      </Link>
    )
  }
  return inner
}

function SubItem({
  icon: Icon,
  title,
  description,
}: {
  icon: React.ComponentType<{ className?: string }>
  title: string
  description: string
}) {
  return (
    <div className="ml-12 glass-subtle p-3 flex gap-2.5">
      <Icon className="h-3.5 w-3.5 text-muted-foreground shrink-0 mt-0.5" />
      <div>
        <div className="text-sm font-medium text-foreground">{title}</div>
        <p className="text-xs text-muted-foreground mt-0.5 leading-relaxed">{description}</p>
      </div>
    </div>
  )
}

function Step({ n, title, children }: { n: number; title: string; children: React.ReactNode }) {
  return (
    <div className="flex gap-3">
      <div className="shrink-0 h-6 w-6 rounded-full bg-moss-700 text-cream-100 flex items-center justify-center text-xs font-mono">
        {n}
      </div>
      <div className="flex-1">
        <span className="font-medium text-foreground">{title}</span>
        <p className="text-muted-foreground mt-0.5 leading-relaxed">{children}</p>
      </div>
    </div>
  )
}

function Faq({ q, a }: { q: string; a: string[] }) {
  return (
    <details className="content-card group">
      <summary className="cursor-pointer p-4 flex items-start gap-3 hover:bg-muted/30 transition-colors">
        <Search className="h-4 w-4 text-moss-700 shrink-0 mt-0.5" />
        <span className="flex-1 text-sm font-medium text-foreground">{q}</span>
        <ArrowRight className="h-4 w-4 text-muted-foreground/40 shrink-0 mt-1 transition-transform group-open:rotate-90" />
      </summary>
      <ul className="px-4 pb-4 pl-12 space-y-1 text-sm text-foreground/80">
        {a.map((line, i) => (
          <li key={i} className="flex gap-2 leading-relaxed">
            <span className="text-moss-600 shrink-0">▸</span>
            <span>{line}</span>
          </li>
        ))}
      </ul>
    </details>
  )
}

function Term({ word, children }: { word: string; children: React.ReactNode }) {
  return (
    <div className="flex gap-3 pb-3 border-b border-border last:border-0 last:pb-0">
      <Flame className="h-3.5 w-3.5 text-bronze shrink-0 mt-1" />
      <div className="flex-1">
        <span className="font-medium text-foreground">{word}</span>
        <p className="text-muted-foreground mt-0.5 leading-relaxed text-sm">{children}</p>
      </div>
    </div>
  )
}

function ShortcutRow({
  shortcut,
  label,
  description,
}: {
  shortcut: string
  label: string
  description: string
}) {
  return (
    <div className="flex items-baseline gap-3 py-1.5">
      <kbd className="shrink-0 inline-flex items-center justify-center min-w-[5rem] h-6 px-2 text-[11px] font-mono font-medium bg-muted border border-border rounded">
        {shortcut}
      </kbd>
      <div className="flex-1">
        <span className="font-medium text-foreground text-sm">{label}</span>
        <span className="text-xs text-muted-foreground ml-2">— {description}</span>
      </div>
    </div>
  )
}

function LogRow({ where, url, what }: { where: string; url: string; what: string }) {
  return (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer"
      className="flex items-baseline gap-3 py-2 px-2 -mx-2 rounded hover:bg-muted/40 transition-colors"
    >
      <RefreshCw className="h-3 w-3 text-moss-600 shrink-0 mt-1" />
      <div className="flex-1 min-w-0">
        <span className="font-medium text-foreground text-sm">{where}</span>
        <p className="text-xs text-muted-foreground leading-relaxed">{what}</p>
      </div>
      <ArrowRight className="h-3 w-3 text-muted-foreground/40 shrink-0 mt-1" />
    </a>
  )
}

function Code({ children }: { children: React.ReactNode }) {
  return (
    <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded text-foreground/90">
      {children}
    </code>
  )
}
