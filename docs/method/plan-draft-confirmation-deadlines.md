# Prazos da confirmação de planos após espera por lock

## Defeito e correção

`public.confirm_plan_draft_atomic` capturava `clock_timestamp()` antes dos
locks de domínio, usuário e rascunho. Se a espera atravessasse o prazo do
rascunho ou da validade solicitada, a confirmação usava um instante antigo
e podia gravar um plano que já deveria ser recusado.

A migration `20261020182949_plan_draft_confirmation_lock_expiry.sql` atualiza
o instante depois dos locks, somente para uma confirmação nova e revisável.
Ela preserva a assinatura, o owner, os privilégios, a configuração e os
demais atributos da função. O corpo original é identificado por SHA-256;
drift interrompe a aplicação. Uma segunda aplicação do mesmo corpo é aceita.

## Contrato preservado

1. A validação inicial de argumentos e do backend continua antes dos locks.
2. Um rascunho já confirmado retorna o resultado original antes da nova
   leitura do relógio. Repetir não muda validade, timestamps, chave ou plano.
   Argumentos preliminarmente inválidos continuam sendo recusados.
3. Um estado não revisável continua retornando `PD422` antes de verificar
   a expiração do rascunho.
4. Para uma confirmação nova, a validade solicitada vencida retorna `22023`;
   rascunho vencido retorna `PD410`; divergência de versão retorna `PD409`.
5. `generated_at`, `resolved_at` e a proteção da prescrição profissional
   nutricional usam o instante atualizado. A prescrição anterior permanece
   intacta; uma confirmação nutricional insere uma nova linha.
6. Validade `NULL` continua permitida. Esta correção não muda o prazo de
   42 dias escolhido pelo produtor Flow, fórmulas ou regras de objetivo.

## Superfície compartilhada

A confirmação atende planos de treino e alimentação do app e usa tabelas e
locks compartilhados com o código legado do WhatsApp. O gerador, o core de
substituição e `save_training_plan_atomic` não são modificados. A confirmação
do app continua sem ativar lembretes de treino; o save legado conserva seu
efeito anterior. Nenhum envio ou rotina remota é ativado por esta mudança.

## Regressões locais de 20/10/2026

- `fixtures/plan_draft_expiration_concurrency.py`: duas esperas observadas
  por PID/XID antes dos prazos, com liberação após o relógio do banco passar
  deles. O corpo antigo confirmou indevidamente nos dois casos; a candidata
  retornou exatamente `PD410` e `22023`, sem efeitos da confirmação.
- `plan_draft_confirmation_expiry.sql`: prioridades dos erros, validade
  `NULL`, ausência de lembretes, replay com versão/chave/validade diferentes,
  DTO original e linhas brutas do usuário, rascunho e plano preservados.
- `fixtures/plan_draft_confirmation_neighbors.py`: sucesso antes da expiração
  com timestamps posteriores ao bloqueio; replay depois da expiração sem
  renovação; sucesso nutricional depois de a prescrição profissional expirar
  durante a espera, preservando integralmente a linha profissional.
- `bodyflow_plan_drafts.sql`: teste existente integral, com assertions e
  papéis preservados, cobrindo proteção profissional ainda vigente,
  conflitos, controle de acesso, criação, confirmação e save legado.
- `plan-draft-service.test.ts`: 23 testes do contrato do serviço passaram.

Os dois drivers contêm somente definições e recebem actors e lifecycle do
executor de QA local. Eles não iniciam banco nem chamam um provedor de IA.

O C5 local usa um stub de Auth com apenas `id`. Para executar o teste antigo
integralmente, o wrapper de QA adicionou as onze colunas nullable usadas pelo
INSERT e a cláusula `USAGE private` já existente nas migrations de julho,
somente dentro da transação desfeita. Papéis, RLS e funções de Auth foram
preservados. Isso não verifica GoTrue ou autenticação HTTP.

## Limites da evidência

Os efeitos da candidata e das confirmações dos actors foram desfeitos.
Fixtures sintéticas duráveis foram removidas por cleanup ensaiado, com
comparação dos quatro bancos antes do COMMIT e leitura posterior ao ACK.
O catálogo, os dados e a sequência de fontes retornaram ao modelo local29.
O PostgreSQL próprio foi parado, sem deixar novos objetos ou dados de QA.

Esses testes não comprovam publicação, HTTP integrado, confirmação durável
do actor B, matriz iOS ou ativação no staging. Não habilitam a captura de
fontes de planos para o acompanhamento semanal nem encerram o marco M3A.
