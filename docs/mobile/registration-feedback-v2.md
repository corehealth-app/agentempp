# Feedback conversacional de registro v2

Implementação do contrato e da apresentação em `packages/agent/src/registration-feedback-v2.ts`. O contrato é independente de `registration.feedback.v1`: seus validadores, recibos, cursor de frases e consumidores continuam inalterados.

## Estado de integração

Esta primeira parte é local e não está ativada nos endpoints ou no iOS. Ainda faltam o armazenamento v2 com CAS da observação clínica, o leitor autenticado, a seleção explícita de versão no servidor e o consumidor nativo compatível. Não confundir os testes destas funções com registro pelo chat, QA conectado ou entrega no TestFlight.

## Fatos e apresentação

O recibo possui identidade do registro e data civil, identidade `Flow AI`, refeição ou atividade, dia oficial opcional, bloco opcional e educação com proveniência. Objetos e enums são fechados; campos extras, números não finitos, identidades incompatíveis e fontes nutricionais não resolvidas são rejeitados.

O renderizador emite seis seções em ordem: registro realizado, valores individuais, resumo, dia, bloco e educação. O recibo guarda fatos e texto educativo versionado. Não aceita outra lista de linhas com números livres. O total da refeição vem do total decimal já confirmado, sem somar novamente floats dos ingredientes.

Cada alimento mantém o ID do log, nome, massa canônica, quantidade de apresentação, fonte nutricional e macros. A apresentação pode usar g, mL, unidades ou medidas. Referências de densidade e porção são as mesmas de `mobile-quantity-display.ts`; permanecem identificadas como estimadas e editáveis. Isso permite apresentar 206 g de leite como 200 mL e 30 g de whey como uma medida, sem mudar a massa ou o cálculo.

`registration-feedback-v2-facts.ts` projeta uma proposta confirmada sobre o conjunto completo dos logs fornecidos pelo backend: dono, chave do evento, instante, tipo de refeição e fatos devem corresponder. Tolera somente a quantização de duas casas dos campos físicos. Mantém o total decimal da proposta. Registro pendente, modificado, grupo incompleto, IDs duplicados ou linhas adicionais não geram enriquecimento. Para atividade, usa a energia persistida do único log comprovado, nunca `kcalEst` ou o gasto agregado do dia.

Para a admissão protegida `ui-v1`, o projetor exige também o testemunho privado de captura, epoch, admissão, lifecycle, operação e log. A chave da operação é diferente da chave original do evento, mas o log pode manter essa chave original: sua igualdade isolada não autoriza tratar o registro como legado. O marcador protegido sem testemunho, ou uma operação/dono incompatível, é recusado. O decoder existente confere a resposta completa do resolver; a procedência é comprovada pela captura SQL, não pela forma do JSON. A lacuna legada de proveniência permite exibir os valores salvos somente para o ID exato comprovado, sem criar classificação.

A captura SQL separa os testemunhos `ui-v1` e `direct-key`. O futuro adaptador deve validar essa distinção antes da projeção: `workoutProof` recebe somente o testemunho protegido `ui-v1`; o legado `direct-key` deve corresponder à chave original e ao log único, sem ser passado como prova protegida. Nunca remover o marcador `ui-v1` para contornar uma prova inválida.

A migração `20261103142948_mobile_registration_feedback_v2_capture.sql` prepara a captura e a tabela privada imutável, com RLS e sem acesso direto, inclusive pelo papel de serviço. Não contém produtor de recibos: commit com CAS, validador fechado, leitura e consumidores continuam pendentes. Sua aplicação não está ativada no staging.

Os valores individuais vêm das colunas efetivamente persistidas dos logs, com duas casas decimais; o total canônico da proposta é preservado separadamente. O resumo oficial do dia tem sua própria representação. Não forçar igualdade entre um novo somatório de floats, o total original e o arredondamento inteiro de calorias do snapshot.

## Dia e proteção clínica

O chamador deve fornecer uma leitura atual, comprovadamente da pessoa e da mesma data do registro, pelo construtor direto de `createCurrentClinicalReadModel`, sem admissão com efeitos, aplicação diária ou fechamento. A próxima integração deve comparar no commit a observação clínica estável e os registros usados; os tipos desta biblioteca não substituem esse CAS.

Consumo exige `daily_snapshot`; cada meta exige sua própria proveniência `daily_snapshot`. As metas de calorias e proteína são independentes. Ausência ou proteção produz null, sem percentual, objetivo presumido ou fallback para fórmula. O saldo alimentar é o oficial; exercício não aumenta a comida disponível. Carboidratos, gordura e exercício não recebem percentuais sem uma meta oficial.

O bloco exige recomposição, política permissiva, disponibilidade e origem `user_progress`. Apresenta saldo e crédito já consolidados, sem crédito por esta mensagem ou promessa de perda física. Inconsistência no bloco opcional o torna indisponível. Um recibo recebido com números inconsistentes é rejeitado. Meta, objetivo e bloco protegidos também não reaparecem no comentário educativo.

## Educação e custo

O catálogo `registration.education.v1` usa templates determinísticos selecionados pelo registro e contexto permitido. A bebida leite/whey tem comentário específico. Outros alimentos identificam a contribuição de energia e proteína dos próprios itens. Atividades distinguem caminhada, força e atividade geral; metas protegidas recebem orientação de pausa. Preferências não são inventadas: quando apenas se sabe que existem, a conversa convida a respeitá-las sem revelar seu conteúdo.

A base da redação sobre movimento é a [ficha da OMS sobre atividade física](https://www.who.int/news-room/fact-sheets/detail/physical-activity), consultada em 03/11/2026: movimento, caminhada e fortalecimento têm valor além do gasto calórico. Não foram incorporadas doses de exercício, prescrição, promessa de hipertrofia ou a afirmação de que caminhar sempre gasta poucas calorias. Os comentários sobre contribuição de nutrientes descrevem os próprios fatos registrados.

Proveniência contém apenas tipo, versão, template e indicador de preferências conhecidas. Não contém prompt, estado de saúde, autoridade, dono ou cursor. A revisão técnica destes templates não representa aceite editorial ou clínico em nome do Roberto. Esse aceite e a conferência do comportamento completo continuam na qualificação da entrega.

Não há chamada de IA, novo custo de inferência, cron, serviço ou infraestrutura neste incremento. Não se ativa o gerador legado que usa identidade profissional. Uma revisão futura do texto exige nova versão do catálogo e preservação do renderizador antigo para os recibos existentes. Indisponibilidade da educação não invalida o registro nem deve repetir o writer.

## Compatibilidade e próximo passo

O armazenamento será separado e privado, com vínculo à proposta original, dados oficiais e observação clínica estável. Repetição deve ler o recibo antes de preparar outro; recibos v1 existentes não serão regenerados. Correção terá seu próprio evento e preservará o recibo histórico original. Reabertura será leitura, sem gravação, seleção de frase ou recompensa.

A integração só poderá retornar v2 a um cliente que declare suporte. Nenhuma flag, migração ou rota foi ativada por este primeiro incremento.
