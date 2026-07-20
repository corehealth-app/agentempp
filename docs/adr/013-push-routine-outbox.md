# ADR 013 — Push e rotina com claim transacional e outbox

- Status: Accepted
- Data: 2026-07-20
- Decisores: Eduardo

## Contexto

O BodyFlow app-first precisa registrar instalações iOS, preferências, lembretes,
hidratação e adesão de rotina antes de integrar APNs. Disparar diretamente de um
cron misturaria cálculo de elegibilidade, token do device e efeito externo. Isso
dificultaria retries, poderia duplicar notificações e permitiria que um estado
desatualizado gerasse lembrete já resolvido.

O sistema também precisa respeitar o dia e o horário local do paciente, inclusive
em mudanças de horário de verão, sem usar o WhatsApp legado como fonte de
identidade ou entrega.

## Decisão

1. `mobile_devices` mantém no máximo uma linha ativa por `installation_id`. Linhas
   inativas preservam o vínculo das entregas históricas; ao trocar de conta com o
   mesmo token comprovado, uma nova identidade de device é criada. Token APNs e
   hash são backend-only e nunca aparecem em DTO, evento ou log.
2. `notification_preferences` guarda opt-in, horário silencioso, limite diário e
   meta opcional de hidratação. O timezone continua canônico em `users`.
3. `reminder_rules` aceita horário local e dias da semana, não uma expressão cron
   arbitrária. Referências de refeição e rotina são validadas por categoria.
4. Hidratação e adesão são append-only e passam por RPCs idempotentes. Hidratação
   atualiza `daily_snapshots.water_consumed_ml` na mesma transação.
5. O scheduler consulta `list_due_reminder_rules`, que retorna apenas IDs e
   instantes UTC em páginas ordenadas por `(scheduled_for, reminder_rule_id)`. A
   conversão usa data e horário locais canônicos e valida a ida e volta do timezone
   para evitar duas ocorrências no retorno do DST e horários inexistentes no avanço
   do relógio.
6. O evento `reminder.rule.due` contém somente `reminderRuleId` e `scheduledFor`,
   com ID determinístico. Retry do scheduler produz o mesmo evento.
7. `claim_reminder_event` é a autoridade de elegibilidade. Sob lock transacional,
   verifica preferência, device ativo, horário silencioso no instante do claim,
   limite diário e fontes oficiais de refeição, hidratação, treino, reavaliação ou
   adesão.
8. Uma ocorrência termina como `queued`, `resolved` ou `suppressed`. Apenas
   `queued` cria uma entrega por device ativo. A unicidade por regra/instante e
   evento/device torna retries idempotentes.
9. `notification_deliveries` é uma outbox auditável. Nesta fase, todas as entregas
   elegíveis permanecem `queued`; nenhum provider APNs é importado ou chamado e
   nenhum estado `sent` é simulado.
10. As RPCs de escrita e claim exigem backend confiável. A descoberta é
    `SECURITY INVOKER`; todas revogam `PUBLIC`, `anon` e `authenticated` e concedem
    execução apenas ao `service_role`.
11. O estado diário expõe meta de hidratação somente quando configurada e itens
    ativos de rotina com a ação oficial mais recente do dia. Dose, prescrição ou
    recomendação não são inferidas.

## Estados e falhas

- `resolved`: o objetivo já foi cumprido; nenhuma entrega é criada.
- `suppressed`: a ocorrência é registrada com motivo, como `quiet_hours`,
  `daily_limit`, `push_disabled`, `no_active_device`, `snoozed`,
  `routine_item_inactive`, `missing_official_context` ou `stale`. Um evento com
  mais de 15 minutos de atraso é auditado como `stale` antes de preferências ou
  deliveries serem criados.
- `queued`: a decisão e as entregas foram persistidas, mas nada foi enviado ao
  provider.
- Falha antes do commit não deixa ocorrência parcial. Retry depois do commit
  devolve o evento existente, mesmo se a regra ou o device forem desativados.

## Consequências

- **+** Estado oficial e efeito externo ficam separados e auditáveis.
- **+** Retry do cron, evento e claim não duplica ocorrência ou entrega.
- **+** O scheduler percorre até 20 páginas de 500 regras; exceder o limite falha
  de forma observável, sem descartar silenciosamente o restante da fila.
- **+** Reassociação de conta não reescreve o proprietário de entregas antigas.
- **+** Token e conteúdo de notificação não circulam no Inngest.
- **+** Horário silencioso e limite são avaliados perto do efeito pretendido.
- **+** O app pode consumir hidratação e rotina sem reimplementar fórmulas.
- **−** Uma integração futura ainda precisa consumir a outbox, autenticar no APNs
  sandbox e tratar tokens inválidos por device.
- **−** CRUD completo de rotina, conteúdo por personalidade e recomendações
  clínicas continuam fora desta fase.

As funções Inngest não foram sincronizadas, os crons Supabase de staging
permanecem inativos, nenhuma credencial APNs foi configurada e produção não foi
alterada por esta decisão.
