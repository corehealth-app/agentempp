# ADR 016 — Rotina normalizada e adesão por ocorrência exata

- Status: Accepted
- Data: 2026-07-23
- Decisores: Eduardo

## Contexto

O BodyFlow precisa permitir que o paciente organize suplementos e medicamentos,
configure vários horários por item, receba lembretes privados e mantenha um
histórico auditável de adesão. O produto é um organizador de lembretes e
registros: não prescreve, recomenda, interpreta nem altera medicamentos ou
doses, e não faz alegações clínicas sobre suplementos.

O domínio existente já usa `routine_items`, `reminder_rules` e
`routine_adherence_logs`. Separar suplementos e medicamentos em subsistemas
paralelos duplicaria ownership, RLS, CRUD, horários, paginação, transições,
daily state e scheduler. Guardar horários ou histórico como JSON no item
enfraqueceria identidade, unicidade, concorrência, paginação e referências
auditáveis.

Uma ação por item/data também é insuficiente. Com horários às 08:00 e 20:00,
registrar a primeira não pode resolver a segunda. Snooze acrescenta outra
exigência: adiar a entrega não pode trocar a identidade da ocorrência original.

## Decisão

1. `routine_items` continua sendo a identidade canônica compartilhada. O tipo
   controlado `supplement` ou `medication` aplica as diferenças de política sem
   criar tabelas, serviços ou APIs duplicados.
2. `reminder_rules` normaliza hora local e dias da semana. Um item possui uma ou
   mais regras. Edições preservam regras logicamente inalteradas e desativam,
   sem reescrever, regras substituídas; logs históricos mantêm IDs estáveis.
3. `routine_adherence_logs` é append-only. Ações novas referenciam paciente,
   item/tipo, regra e ocorrência. Correções apontam para o log anterior com
   `supersedes_log_id`; nenhuma ação é atualizada ou excluída.
4. `pending` é estado derivado de uma regra elegível sem ação. Persisti-lo
   criaria eventos artificiais, exigiria fan-out antecipado para todos os dias e
   poderia divergir após mudança de timezone, regra ou ciclo de retry.
5. `missed` é derivado imediatamente após o fim do dia local e também persistido
   redundantemente por um finalizador idempotente. A derivação mantém leitura
   correta quando o worker atrasa; a linha persistida fornece auditoria,
   paginação, correção append-only, isolamento de retry e prova operacional de
   que a ocorrência vencida foi finalizada.
6. A identidade de ocorrência é a regra mais o instante UTC original
   `scheduled_for`, no contexto do paciente e do item/tipo. O banco valida a
   regra contra timezone, dia da semana, hora local e round-trip DST, e deriva
   uma chave SHA-256. O cliente nunca fornece essa chave.
7. Snooze conserva a regra, o `scheduled_for` original e a mesma chave. Apenas
   `snoozed_until` define quando tentar o follow-up. Retry, claim, leitura e
   finalização correlacionam a ocorrência pela identidade original.
8. CRUD, aceite legal e ações passam pelo BFF autenticado e por RPCs backend-only
   transacionais. Não há escrita direta de `anon` ou `authenticated`; funções
   privilegiadas têm search path fixo, validação de backend confiável, revoke
   explícito e grant somente para `service_role`.
9. Lembretes de medicamento usam texto neutro e `personality='default'`, sem
   persuasão por persona, streak, recompensa ou culpa. O preview de rotina é
   `private` por padrão; opções explícitas permitem nome ou nome+dose apenas na
   renderização futura do push.
10. Eventos Inngest, métricas e outbox carregam IDs, timestamps e o modo de
    preview controlado. Nome, dose, texto legal, token e payload bruto não entram
    nesses canais. A preferência não autoriza copiar conteúdo privado para
    observabilidade.

## Alternativas rejeitadas

### Tabelas separadas para suplemento e medicamento

Duplicariam schedules, logs, índices, RLS, RPCs, DTOs e regras de daily state.
Correções de concorrência ou privacidade teriam de permanecer sincronizadas em
dois domínios. O tipo controlado e as políticas legais/clínicas expressam a
   diferença sem duplicação estrutural.

### Horários e histórico em JSON no item

JSON simplificaria a primeira escrita, mas perderia FKs de ownership/tipo, IDs
estáveis de horário, keyset pagination eficiente, unicidade relacional e locks
por ocorrência. Também favoreceria reescrita de histórico em PATCH.

### Persistir `pending`

Exigiria materializar ocorrências futuras e reconciliá-las após edição de regra,
timezone ou DST. Ausência de ação já representa esse estado sem uma linha falsa.

### Manter apenas `missed` derivado

A leitura continuaria correta, mas histórico e correção dependeriam para sempre
de recomputar regras antigas. A persistência idempotente cria uma âncora de
auditoria sem tornar o worker fonte exclusiva do estado público.

### Trocar o instante original pelo horário do snooze

Criaria uma nova identidade a cada adiamento, permitindo entregas e ações
duplicadas e dificultando correlação de retry. O follow-up é outra tentativa da
mesma ocorrência, não uma nova ocorrência.

### Mensagem de medicamento orientada por persona

Personalização persuasiva pode transformar um lembrete neutro em pressão de
adesão ou sugestão clínica. Medicamento permanece neutro e privado mesmo quando
o paciente escolhe outra persona para o coach.

## Consequências

- **+** Suplementos e medicamentos compartilham uma única arquitetura de
  ownership, segurança, horários, histórico e estado diário.
- **+** Duas ocorrências do mesmo item/dia permanecem independentes.
- **+** Edição de horário, snooze, retry e correção preservam trilha auditável.
- **+** Leitura de `missed` não depende da pontualidade do scheduler.
- **+** O conteúdo de medicamento permanece fora de eventos técnicos e privado
  por padrão.
- **−** O modelo exige RPCs e índices específicos para concorrência,
  finalização e paginação por ocorrência.
- **−** A redundância controlada de `missed` exige teste de paridade entre estado
  derivado e linha persistida.
- **−** Mudanças de timezone e ciclo de vida exigem snapshots históricos para
  finalizar dias anteriores de forma determinística.

## Validação e rollout

Testes locais cobrem contratos, transações, RLS/grants, DST, múltiplos horários,
snooze, correção, cursor, retries, privacidade da outbox e regressão das fórmulas
do estado diário. Aplicação das migrations, SQL runtime, tipos gerados e canário
sintético na branch Supabase de staging pertencem à Task 9. Esta decisão não
autoriza produção, deploy, provider send, ativação de cron ou acesso a dados
reais.
