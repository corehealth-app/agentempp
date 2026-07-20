# BodyFlow Push And Routine Design

**Status:** aprovado para execucao pelo comando "Pode continuar" em 2026-07-20.

## Objetivo

Preparar o backend app-first para dispositivos iOS, preferencias de notificacao,
lembretes recorrentes e registros de hidratacao/adesao. Esta fase deve permitir
testar todo o ciclo ate a fila de entrega sem possuir um app iOS, credenciais APNs
ou integracoes externas reais.

## Limites da fase

- O WhatsApp legado nao participa do fluxo novo.
- Nenhuma requisicao e enviada ao APNs nesta fase. Entregas ficam em `queued`
  ate existir credencial sandbox e app com entitlement.
- Os 34 crons da branch Supabase staging permanecem inativos. O scheduler novo e
  uma funcao Inngest registrada, mas nao sera sincronizada nem executada em live.
- O Prompt 07 implementara conteudo e selecao de templates por personalidade.
  Esta fase persiste somente `template_key` e a personalidade solicitada.
- O Prompt 09 ampliara o CRUD de suplementos e medicamentos. Esta fase cria o
  nucleo privado de itens e adesao necessario para registrar `taken`.
- Medicamentos e suplementos sao lembretes cadastrados. O backend nao recomenda,
  prescreve, altera dose ou produz claims medicos.

## Arquitetura

### Identidade e dispositivos

`mobile_devices` armazena uma instalacao iOS por paciente e ambiente APNs. O token
e mantido em uma tabela backend-only, com hash para unicidade e sem aparecer nos
DTOs, logs ou eventos Inngest. Um novo token da mesma instalacao substitui o
anterior; um token reassociado deixa de pertencer a conta anterior para evitar
push de dados apos troca de conta.

### Preferencias

`notification_preferences` possui opt-in global, horario silencioso, limite diario
e meta opcional de hidratacao. O timezone canonico continua em `users.timezone`.
Horarios silenciosos podem atravessar meia-noite e nunca sao ignorados por tipo de
lembrete.

### Regras e rotina

`reminder_rules` representa horarios locais simples e dias da semana, sem aceitar
cron arbitrario do cliente. As categorias sao refeicao, hidratacao, suplemento,
medicamento, treino, reavaliacao, conteudo e reengajamento.

`routine_items` guarda o minimo privado para suplemento/medicamento. O catalogo e
somente leitura nesta fase; o Prompt 09 adicionara os endpoints de CRUD.

`hydration_logs` e `routine_adherence_logs` sao append-only. Cada mutacao usa a
idempotencia da API mobile e uma chave unica no banco. A hidratacao atualiza o
`daily_snapshots.water_consumed_ml` na mesma transacao e nunca altera formula de
calorias, bloco 7700 ou fechamento do dia.

### Ocorrencias e entrega

O scheduler converte regras vencidas em `reminder_events` por uma RPC transacional.
A unicidade por regra/instante impede duplicidade por retry. Antes de criar uma
entrega, ele verifica preferencia, horario silencioso, limite diario, dispositivo
ativo e estado oficial:

- refeicao: gap ainda aberto;
- hidratacao: meta configurada ainda nao atingida;
- suplemento/medicamento: ocorrencia ainda sem adesao resolvida;
- treino: nenhum treino aplicavel ja registrado;
- reavaliacao: reavaliacao ainda devida.

Contextos sem fonte oficial suficiente sao suprimidos, nunca enviados por
suposicao. `notification_deliveries` registra canal, template, personalidade,
status e erro tecnico sem payload sensivel. Nesta fase, uma ocorrencia elegivel
termina como `queued` com entrega `queued`; nao existe estado `sent` ficticio.

## Seguranca

- Todas as tabelas em `public` usam RLS.
- `authenticated` recebe apenas SELECT nas colunas seguras das proprias linhas.
- Escritas passam pelo BFF com `service_role` e por RPCs que chamam
  `private.assert_trusted_backend()`.
- Tokens APNs e contexto interno nao sao selecionaveis por clientes autenticados.
- Eventos Inngest carregam apenas IDs tecnicos.
- Nenhuma mensagem, email, telefone, token ou segredo entra em telemetria.

## API mobile v1

- `POST /api/mobile/v1/devices`
- `DELETE /api/mobile/v1/devices/:id`
- `GET /api/mobile/v1/notification-preferences`
- `PATCH /api/mobile/v1/notification-preferences`
- `GET /api/mobile/v1/reminders`
- `POST /api/mobile/v1/reminders`
- `PATCH /api/mobile/v1/reminders/:id`
- `POST /api/mobile/v1/routine/hydration`
- `POST /api/mobile/v1/routine/supplements/:id/taken`
- `POST /api/mobile/v1/routine/medications/:id/taken`

Toda mutacao exige `Idempotency-Key`. DELETE de device desativa a instalacao em
vez de apagar o historico de auditoria.

## Falhas e retries

- Conflito de chave idempotente retorna 409.
- Repeticao da mesma chave devolve a mesma resposta.
- Regra inativa, item de outro usuario ou tipo divergente retorna erro explicito.
- Falha antes da claim nao cria evento parcial.
- Uma claim abandonada pode ser retomada depois do lease; uma entrega `queued` ou
  resolvida nao e criada novamente.
- Falha futura do APNs sera registrada por device e podera desativar token invalido,
  mas essa integracao nao faz parte desta fase.

## Testes de aceite

- Token nunca aparece em DTO, evento ou log.
- Dois retries criam um device, um log de hidratacao e uma ocorrencia.
- Quiet hours e limite diario suprimem a fila com motivo auditavel.
- Evento resolvido nao produz entrega.
- Hidratacao soma atomicamente no dia local correto.
- `taken` so aceita item pertencente ao paciente e do tipo da rota.
- RLS impede leitura cruzada e grants nao expoem token/metadata interna.
- Todos os testes rodam em transacao e deixam staging sem dados sinteticos.
