# Jornada social — fundação privada do ranking

Estado: as sete migrações sociais, até `20261119005845_journey_social_auth_revocation.sql`, foram aplicadas ao staging `xitugspwfxkcluxvrdeg` em 18/11/2026 (R202). **A Jornada social continua sem liberação no app.** O plano aprovado de 03/11/2026 segue ativo, com todos os requisitos restantes obrigatórios. Os contratos HTTP, a interface operacional e a reconciliação persistente passaram pela qualificação local; QA conectado com identidades reais de teste e distribuição continuam necessários. Os contratos nativos estão descritos em [Jornada social no iOS](journey-social-ios-contracts.md).

## Aplicação do esquema no staging

O pacote usou os arquivos SQL do commit `022607b7`, com verificações dentro de
uma única operação atômica. Um ensaio no PostgreSQL 17.6 real do staging
conferiu as 27 funções novas, as sete tabelas privadas, os privilégios e as
917 funções anteriores; depois reverteu todos os objetos e registros de
histórico novos. A aplicação definitiva passou pelas mesmas verificações.
Uma consulta independente confirmou os sete registros de migração com hashes
iguais aos arquivos de origem e a preservação das 917 funções anteriores.

As tabelas novas ficaram vazias, com RLS, sem políticas de acesso direto e sem
permissões diretas para `anon`, `authenticated` ou `service_role`. As funções
públicas permanecem restritas ao backend. Também foram exercidas recusas de
identidade ausente sem criar contas ou registros de teste no staging.

Isso qualifica a aplicação do esquema, não o fluxo completo de uma pessoa no
app. Não houve build de servidor, troca de endereço, ativação de capacidade ou
novo TestFlight nesta etapa. O build 1.0(20) e seus servidores foram preservados.

## Dados e autoridade

A migração `20261118144440_journey_social_weekly_foundation.sql` acrescenta três tabelas privadas com RLS sem políticas de acesso direto: participação, recibos de operação e bloqueios direcionais. Nenhuma rotina atual é substituída. Nenhum cálculo ou writer de XP, calorias, fechamento diário ou treino é alterado.

A participação exige apelido escolhido pela pessoa e comprovante da versão `journey-social.v1`. O comprovante é um identificador técnico; a interface ainda precisa apresentar a informação de privacidade correspondente antes de obter o aceite. Não derivar o apelido do nome ou e-mail do cadastro. Identificadores públicos aleatórios diferem dos IDs de domínio e de Auth. Sair limpa o apelido visível e remove a pessoa das próximas leituras. As tabelas acompanham a exclusão do usuário por FK com cascade.

Os wrappers SQL são executáveis somente pelo backend `service_role`, validam o vínculo original entre domínio e Auth e recusam contas bloqueadas/excluídas. O transporte futuro deve primeiro validar a sessão viva e o acesso do usuário; os argumentos desses wrappers não são autoridade fornecida pelo cliente. Uma troca do vínculo Auth não transfere silenciosamente o consentimento antigo.

- `read_journey_social_profile(uuid, uuid)` lê o próprio estado; ausência retorna revisão zero sem criar perfil.
- `mutate_journey_social_profile(uuid, uuid, uuid, bigint, boolean, text, text)` exige UUID de operação e revisão esperada. Comandos concorrentes usam o lock da própria conta. Repetir retorna o recibo original junto ao estado atual; conteúdo diferente ou revisão obsoleta é conflito. O recibo não contém o apelido histórico e não recoloca quem já saiu.
- `read_journey_weekly_ranking(uuid, uuid, integer)` usa o relógio do servidor e a data civil oficial do leitor. A semana vai de segunda a domingo. Somente `daily_snapshots.day_closed = true` e `xp_earned` do intervalo entram na soma. Pontos provisórios, totais de toda a jornada e dias futuros ficam fora. A leitura não cria registros ou recompensas.

A projeção exclui quem não consentiu, contas bloqueadas/excluídas, perfis suspensos e bloqueios em ambas as direções. As posições são calculadas sobre o conjunto visível: empates compartilham posição (`1, 1, 3`). A ordenação por identificador público estabiliza os empates sem desempatar a posição.

`20261119005845_journey_social_auth_revocation.sql` acrescenta a verificação do
bloqueio e da exclusão lógica no Auth, além do estado da conta de domínio.
Contas sem confirmação também ficam fora da projeção dos colegas. Os gateways
de paciente e operador serializam a identidade do Auth com o trabalho já
admitido, preservando a sessão original e sem renovar ou escrever no Auth.
Banimento expirado permite novamente a admissão normal. Os testes de revogação
usam fixtures transacionais e duas conexões reais, nas duas ordens da disputa,
sem gravar XP. Isso não implementa a exclusão completa de conta pelo app.

A resposta dos colegas admite somente `member_id`, `nickname`, `rank`, `weekly_xp` e `is_you`. Não expõe Auth, ID interno, nome de cadastro, calorias, peso, gordura, metas ou proteções clínicas. O leitor inicial continua compatível, limitado a 1–100 participantes e com `has_more`. O novo `read_journey_weekly_ranking_page` oferece cursor ligado ao membro público do leitor, à data civil e a um digest do conjunto visível. Mudança de XP, participação ou bloqueio exige atualizar a lista; não se mantém um snapshot que reapresente quem saiu. O cursor não concede autoridade e não contém IDs internos ou fatos clínicos. A função privada com relógio parametrizado serve aos testes determinísticos e não recebe EXECUTE de nenhum papel da API.

## Verificação e próximas integrações

`supabase/tests/journey_social_weekly_foundation.sql` executa o contrato em PostgreSQL e reverte as identidades sintéticas. Cobre ausência sem escrita, propriedade, papel de backend, consentimento, replay/conflito, saída, XP de dias fechados, empates, limite, fuso/meia-noite, lista pública restrita, bloqueio bidirecional, RLS/privilégios e cascatas de exclusão. A qualificação local também exerceu duas conexões concorrentes e 500 participantes/3.500 dias sintéticos, sem usar dados ou serviços externos.

Antes de ativar: contratos HTTP fechados com sessão viva e identidade original, opt-in/saída/controles no iOS, telas operacionais de moderação, QA A/B com persistência e privacidade, distribuição e conferência da versão instalada. A missão em dupla, conquista sem XP extra e Android continuam obrigatórios no plano geral.

## Bloqueio, denúncia e operação

A recuperação de resposta perdida e seu cancelamento auditável estão
documentados em [Recuperação de operações](journey-social-operation-recovery.md).
O esquema dessa dependência foi incluído na aplicação R202; isso não ativa as telas.

`mutate_journey_social_block` e `submit_journey_social_report` compartilham o namespace idempotente e a revisão do próprio perfil. Retentar não reaplica um bloqueio retirado. Bloqueios ocultam o colega nos dois sentidos; a lista própria permite desfazê-los mesmo após sair do ranking. Apelidos retirados não são conservados nessa lista. As denúncias admitem somente os motivos `nickname`, `harassment`, `spam` e `other`, sem texto clínico livre. O mesmo motivo ainda pendente por pessoa/alvo é deduplicado. Nenhuma denúncia suspende um perfil automaticamente.

`read_journey_social_reports`, `moderate_journey_social_profile` e `resolve_journey_social_report` exigem o papel operacional atual `operations_admin` ou `master_admin`. O transporte deve derivar os argumentos de ator da sessão administrativa, nunca do corpo enviado pelo cliente. `is_admin()` amplo não autoriza essas ações. A fila não expõe a identidade do denunciante. Suspender/restaurar e resolver/descartar usam UUID de operação, revisão e recibo auditável sem apelido histórico ou valores de saúde. A retirada de consentimento prevalece sobre restaurar a moderação; revogar o papel impede também a leitura de recibos antigos. Resolver uma denúncia não suspende alguém implicitamente: as duas ações são explícitas.

A serialização por operador torna duas resoluções simultâneas do mesmo comando uma aplicação e uma repetição. Bloqueios usam lock compatível com as FKs para permitir A e B bloquearem um ao outro sem deadlock. O teste reproduzível `supabase/tests/journey_social_concurrency.py --registry /caminho/LOCAL-ARENA.json` exige uma cópia local própria, socket Unix privado e identidade PostgreSQL conferida. Cria UUIDs sintéticos novos e apaga somente seus registros; não cria, apaga ou reinicia banco/serviço. O contrato SQL adicional está em `supabase/tests/journey_social_controls.sql`.
