# Jornada social — fundação privada do ranking

Estado: dependência de T6 implementada e qualificada localmente; **não ativada no app nem aplicada no staging**. O plano aprovado de 03/11/2026 continua integralmente aberto. Os controles de bloqueio, denúncia, moderação, paginação e a interface precisam ser integrados e qualificados antes da exposição.

## Dados e autoridade

A migração `20261118144440_journey_social_weekly_foundation.sql` acrescenta três tabelas privadas com RLS sem políticas de acesso direto: participação, recibos de operação e bloqueios direcionais. Nenhuma rotina atual é substituída. Nenhum cálculo ou writer de XP, calorias, fechamento diário ou treino é alterado.

A participação exige apelido escolhido pela pessoa e comprovante da versão `journey-social.v1`. O comprovante é um identificador técnico; a interface ainda precisa apresentar a informação de privacidade correspondente antes de obter o aceite. Não derivar o apelido do nome ou e-mail do cadastro. Identificadores públicos aleatórios diferem dos IDs de domínio e de Auth. Sair limpa o apelido visível e remove a pessoa das próximas leituras. As tabelas acompanham a exclusão do usuário por FK com cascade.

Os wrappers SQL são executáveis somente pelo backend `service_role`, validam o vínculo original entre domínio e Auth e recusam contas bloqueadas/excluídas. O transporte futuro deve primeiro validar a sessão viva e o acesso do usuário; os argumentos desses wrappers não são autoridade fornecida pelo cliente. Uma troca do vínculo Auth não transfere silenciosamente o consentimento antigo.

- `read_journey_social_profile(uuid, uuid)` lê o próprio estado; ausência retorna revisão zero sem criar perfil.
- `mutate_journey_social_profile(uuid, uuid, uuid, bigint, boolean, text, text)` exige UUID de operação e revisão esperada. Comandos concorrentes usam o lock da própria conta. Repetir retorna o recibo original junto ao estado atual; conteúdo diferente ou revisão obsoleta é conflito. O recibo não contém o apelido histórico e não recoloca quem já saiu.
- `read_journey_weekly_ranking(uuid, uuid, integer)` usa o relógio do servidor e a data civil oficial do leitor. A semana vai de segunda a domingo. Somente `daily_snapshots.day_closed = true` e `xp_earned` do intervalo entram na soma. Pontos provisórios, totais de toda a jornada e dias futuros ficam fora. A leitura não cria registros ou recompensas.

A projeção exclui quem não consentiu, contas bloqueadas/excluídas, perfis suspensos e bloqueios em ambas as direções. As posições são calculadas sobre o conjunto visível: empates compartilham posição (`1, 1, 3`). A ordenação por identificador público estabiliza os empates sem desempatar a posição.

A resposta dos colegas admite somente `member_id`, `nickname`, `rank`, `weekly_xp` e `is_you`. Não expõe Auth, ID interno, nome de cadastro, calorias, peso, gordura, metas ou proteções clínicas. O primeiro leitor é limitado a 1–100 participantes e informa `has_more`; não há ainda cursor de continuação e não se pode apresentar essa página como o ranking completo. A função privada com relógio parametrizado serve aos testes determinísticos e não recebe EXECUTE de nenhum papel da API.

## Verificação e próximas integrações

`supabase/tests/journey_social_weekly_foundation.sql` executa o contrato em PostgreSQL e reverte as identidades sintéticas. Cobre ausência sem escrita, propriedade, papel de backend, consentimento, replay/conflito, saída, XP de dias fechados, empates, limite, fuso/meia-noite, lista pública restrita, bloqueio bidirecional, RLS/privilégios e cascatas de exclusão. A qualificação local também exerceu duas conexões concorrentes e 500 participantes/3.500 dias sintéticos, sem usar dados ou serviços externos.

Antes de ativar: comandos de bloqueio/denúncia, moderação com autorização operacional específica (não `is_admin()` amplo), cursor, contratos HTTP fechados, opt-in/saída/controles no iOS, QA A/B com persistência e privacidade, distribuição e conferência da versão instalada. A missão em dupla, conquista sem XP extra e Android continuam obrigatórios no plano geral.
