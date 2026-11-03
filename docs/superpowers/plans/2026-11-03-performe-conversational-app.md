# Performe AI — implementação conversacional aprovada

> Executar com `superpowers:executing-plans`, TDD e uma revisão independente do incremento completo. Esta é a especificação operacional aprovada pelo usuário em 03/11/2026; substitui a prioridade Android anterior, sem remover obrigações finais.

## Objetivo e autoridade

Reproduzir no app a experiência conversacional e a riqueza das respostas do antigo WhatsApp, sem ativar seu transporte, produção ou identidade profissional. Referências visuais: seis mockups de 03/11/2026 no diretório privado `generated_images/01a0f35b-2408-7940-bba7-205ba94db450`; retorno de Roberto enviado no mesmo chat. São exemplos visuais, não evidência funcional nem números clínicos aprovados.

O Flow se identifica como IA. Após cada registro real: confirmação curta, valores individuais, total, percentuais/saldo oficiais do dia, bloco 7.700 elegível consolidado e educação específica sobre o registro e preferências conhecidas. O exercício não aumenta comida disponível; o bloco não antecipa créditos nem promete perda física equivalente. Preservar protocolos/guardas clínicos, consentimentos, histórico, quotas e retenção aprovados.

## Contratos e invariantes

- Quatro abas: Flow, Alimentação, Treino, Jornada. Preservar Perfil, Biblioteca, rotina, reavaliações e destinos equivalentes de links/notificações antigas.
- Consumo/atividade inequívocos com dados suficientes registram ao enviar. Pergunta, futuro, hábito, negação e terceiro não registram. Usar guard executável e serviços de domínio; não liberar writers legados ao LLM.
- Texto, câmera, galeria, áudio e edição compartilham resolução. Na política de consumo mobile, arroz/feijão sem preparo assumem cozido, mostrado e editável; explícitos, marca/rótulo e correção ativa prevalecem. Sem alteração implícita do legado.
- Leite em mL, whey em medidas com referência estimada editável. Preservar a diferença entre quantidade de leite e massa total da bebida. Dados ausentes pedem uma pergunta específica; fonte desconhecida não vira zero nem calorias manuais obrigatórias.
- Lápis por item, Salvar aplica diretamente. Desfazer em até cinco minutos, somente versão compatível e dia aberto, com compensação/recibo duráveis no servidor.
- Comandos duráveis, idempotentes além do TTL HTTP, fila local protegida por conta e timeline paginada. Timeout reconcilia; repetição técnica não duplica, duas refeições iguais legítimas continuam distintas. Leituras não escrevem nem concedem XP.
- Feedback v2 separado/compatível com v1: fatos por alimento/atividade, resumo oficial e bloco elegível, educação e proveniência. Números não são inventados pela IA. Preservar recibos históricos; falha de educação não repete o registro.
- Alimentação separa planejado/realizado, Dia/Semana. Treino persiste exercícios/séries/repetições/carga, atividades livres e compartilhamento com prévia iniciado pela pessoa; marcar exercício não duplica o treino.
- Ranking geral por adesão e apelido, sem saúde pública; semana segunda–domingo pela data civil oficial, XP oficial, empates compartilham posição, saída/bloqueio/denúncia/moderação.
- Dupla por convite aceito, metas individuais fixadas no início e conclusão dos dois. Conquista sem XP extra. Sem meta válida não atribuir desafio; pausa clínica sem punição.

## Sequência e verificação

- [ ] T1: caracterizar e corrigir resolução nutricional compartilhada com opção de política explícita; dourados dos relatos reais e vizinhos, preservando legado.
- [ ] T2: feedback v2, leitores clínicos sem efeitos, compatibilidade/replay v1, educação contextual e testes de números indisponíveis/sem meta/bloco protegido.
- [ ] T3: comandos/timeline e operações diretas de registro/correção/desfazer com propriedade, epoch, versão, concorrência e reabertura.
- [ ] T4: Flow iOS, quatro abas, captura multimodal, fila protegida, cartões e edição; QA conectado com refeição/atividade, correção, reinício e isolamento.
- [ ] T5: Alimentação/Treino Dia/Semana, execução por exercício e compartilhamento nativo; registro único por sessão, histórico preservado.
- [ ] T6: Jornada social, ranking consentido, dupla e moderação, sem novos pontos por retry/edição/desfazer.
- [ ] T7: gates integrados, acessibilidade física, performance, staging, TestFlight, versão instalada/aceite Roberto; depois paridade Android.

Para cada implementação: RED → GREEN, testes vizinhos e regressão, typecheck/lint/build afetados e revisão do diff. Testar explícito versus inferido, rótulo/preparo, duas refeições iguais, resposta perdida depois do commit, concorrência, conta A/B, fuso/meia-noite/dia fechado, desfazer expirado/obsoleto, falha de feedback, percentuais sem meta e crédito/recompensa única. Não enfraquecer testes anteriores para aceitar comportamento novo fora de sua política opt-in.

Primeiro candidato de Roberto: registra no chat, recebe todos os blocos, corrige pelo lápis e encontra os mesmos valores nas abas após reabrir. Publicar por capacidade com rollback compatível e QA real; não declarar entrega por teste local.

## Ambientes e escopo preservado

Reutilizar worktree/branch e staging `xitugspwfxkcluxvrdeg`, projeto BFF `prj_NTrnUNFXfmddMuci3VWjalfAoejW`, time `team_UERmEwgxRUaDvbvd22K1Iqde`, `gru1`. Proibido tocar Supabase antigo `xuxehkhdvjivitduarvb`, `agentempp.vercel.app` ou `scripts/deploy.sh`. Sem novo ambiente pago por conveniência. Registrar lifecycle/closeout de recursos temporários.

Recuperação de senha, assinaturas, Android, Biblioteca/editorial, demais 20 áreas contratuais e aceite final continuam no plano geral. Este arquivo não atribui aprovação editorial, clínica, de lojas ou de contratos em nome de terceiros.
