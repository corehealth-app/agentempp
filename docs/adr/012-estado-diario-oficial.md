# ADR 012 — Estado diário oficial compartilhado

- Status: Accepted
- Data: 2026-07-20
- Decisores: Eduardo

## Contexto

O endpoint mobile `/today` devolvia apenas o snapshot, itens de refeição e treinos.
Ele não representava gaps, pendências, qualidade do fechamento, hidratação ou bloco
7700 e calculava campos derivados dentro do BFF. Isso permitiria que iOS, WhatsApp
e um futuro Android apresentassem interpretações diferentes do mesmo dia.

O sistema já possuía fórmulas canônicas em `@mpp/core`, recálculo atômico de
snapshots após refeições e treinos e fechamento idempotente. Faltava uma visão de
aplicação única sobre essas fontes.

## Decisão

1. `@mpp/core/daily-state` define o DTO e combina somente entradas explícitas por
   meio de uma função pura.
2. `@mpp/agent/daily-state-service` carrega perfil, configuração, snapshot, logs,
   padrão de refeições, pendências e progresso, sempre delimitados por paciente e
   data local.
3. `GET /api/mobile/v1/today` devolve esse estado sem reimplementar cálculos.
4. “Restam” usa ingestão menos meta sem exercício; saldo líquido usa ingestão menos
   meta menos exercício. Ambos chamam o motor canônico.
5. Dia aberto é provisório. Gap não resolvido no fechamento é informação
   insuficiente e não um fracasso do paciente.
6. O bloco mostra apenas `user_progress` persistido, sem crédito projetado para o
   dia atual.
7. Pendências são reduzidas a metadados públicos. Payload bruto e evidências
   internas permanecem no servidor.
8. Módulos ainda inexistentes são declarados como `not_implemented`; nenhum valor
   substituto é inventado.
9. `calculation_version=bodyflow.daily-state.v1` identifica a semântica. Alteração
   de fórmula incrementa a versão; quebra de JSON exige nova versão da API.

## Idempotência e recálculo

- Propostas e edições mobile são protegidas pelo ledger de idempotência do BFF.
- Confirmações reutilizam os registros atômicos de refeição/treino, que recalculam
  o snapshot pela soma dos logs e deduplicam retries pela chave de origem.
- O fechamento diário reutiliza `finalize_daily_close_atomic` e a política
  canônica do bloco.
- Esta decisão não cria endpoint de fechamento manual nem migration de banco.

## Consequências

- **+** iOS, WhatsApp e futuro Android podem consumir a mesma semântica oficial.
- **+** O app permanece uma camada de apresentação, sem fórmulas concorrentes.
- **+** Origens e qualidade do dado ficam explícitas para UI e observabilidade.
- **+** A versão permite detectar drift entre cliente e backend.
- **−** A leitura agrega mais fontes e depende da disponibilidade delas.
- **−** Hidratação completa, suplementos e medicamentos aguardam seus domínios.

Nenhuma migration, consulta live ou alteração de ambiente foi realizada nesta
decisão.
