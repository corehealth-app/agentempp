# Tutorial inicial guiado: requisito adicional do beta iOS

## Autoridade e situação

Eduardo pediu em 02/10/2026 um tutorial inicial para o usuário entender tudo que pode fazer no app atualmente. **Autorizado para implementar ao final do refinamento; ainda não implementado.** Esta especificação propõe detalhes de UX/engenharia para o Claude Code executar sem reabrir autorizações rotineiras. A aceitação visual continua com Eduardo.

## Resultado esperado

O usuário deve saber onde começar, quais são as cinco áreas, como conversar com Flow, como registrar/revisar/confirmar, onde acompanhar resultados e como retornar à ajuda. Explicar somente comportamentos existentes e liberados para aquela sessão; não prometer conteúdo publicado, histórico, geração, integração ou automação indisponível.

## Jornada proposta

- Primeira entrada elegível, depois da autenticação e do onboarding funcional/consentimentos existentes, já com a sessão resolvida. Não colocar tutorial sobre a Launch Screen nem atrasar a primeira tela utilizável.
- Oferecer uma apresentação breve com **Começar**, **Agora não**, **Voltar**, **Próximo** e conclusão clara. Não forçar a leitura completa.
- Percurso guiado por áreas, com módulos curtos para capacidades secundárias. O número de passos deve ser o mínimo que preserve entendimento; não transformar todos os detalhes em sequência obrigatória longa.
- Disponibilizar **Conhecer o app / Rever tutorial** no Perfil para rever áreas específicas e o percurso completo, sem repetir onboarding ou consentimentos.
- Reutilizar navegação/componentes atuais. Se houver foco visual em um controle, ancorar em geometria real e oferecer alternativa textual acessível; não depender de recortes frágeis ou coordenadas fixas.
- Durante o passeio, explicar antes de abrir uma ação. Não enviar prompt ao LLM, disparar câmera/microfone/permissão, confirmar registro, ativar plano, alterar lembrete, publicar ou salvar dado de saúde apenas para demonstrar.
- Ao fechar, preservar contexto do usuário: aba/pilha/rascunho/posição de leitura, inclusive quando iniciou o replay dentro de um formulário. Não disputar sheets, alertas, deep links ou processamento já em andamento.

## Cobertura do conteúdo

Validar cada item no código/rota/capability real antes de escrever o texto final. Esta lista é cobertura, não promessa de funcionalidades novas:

| Área | O que explicar |
|---|---|
| Hoje | Resumo do dia, Restam/Excedente para comida, consumo/meta, atualização e dados desatualizados; onde ver detalhes/protocolo e histórico. Valores oficiais, sem fórmulas inventadas |
| Flow | Onde abrir a conversa, perguntas sobre dados e sugestões existentes, envio pendente, continuar rascunho durante resposta, retry e cancelamento da espera local; sugestões precisam de revisão/confirmação |
| Registrar | Logo central, refeição/treino/peso/hidratação; texto/foto/áudio conforme opções reais; revisar estimativas e só então confirmar; erro/retry preserva trabalho |
| Plano | Plano atual, detalhes, rascunhos para revisar, importar por formatos realmente suportados e diferença entre importar/revisar/confirmar/ativar |
| Progresso | Medidas/peso/data, indicadores e bloco disponíveis; ausência de dados não é progresso inventado |
| Rotina | Acesso pela rota existente, horários futuros, quando não há ocorrência elegível, ações confirmadas/conflitos; não sugerir que horário passado é automaticamente executável |
| Biblioteca | Onde acessar, filtros/idiomas, Todos/Salvos, leitura/salvar/concluir se disponíveis; mostrar honestamente o vazio sem revelar rascunhos editoriais |
| Perfil | Dados/preferências/persona efetivamente disponíveis, lembretes locais e ajuda; não pedir notificações automaticamente pelo tutorial |
| Mascote / recursos secundários | Incluir só se o código e a sessão realmente os expõem, explicando os dados reais sem criar recompensas/histórico |

## Estado e isolamento

- Preferir estado local pequeno e versionado, associado à identidade estável da conta quando aplicável; não criar tabela/API nova para este escopo.
- Separar “concluído”, “agora não” e passo em andamento conforme necessário, com comportamento explícito para reinstalação/atualização. Não converter abandono em conclusão.
- Limpar apresentação transitória no logout/troca de conta. A conclusão de QA A não pode suprimir indevidamente a introdução de QA B ou revelar conteúdo/etapa privada de A.
- Respostas assíncronas e callbacks do tutorial precisam respeitar sessão/operação atual. Nada deve reaparecer tarde sobre outra conta ou outra sheet.
- Considerar deep link pendente e conta já existente no beta: oferecer apresentação sem sequestrar navegação nem perder trabalho.
- Persistir somente preferências de apresentação sem segredos/dados de saúde. Usar os mecanismos existentes de armazenamento/isolamento quando adequados; nenhuma dependência nova.

## Visual, acessibilidade e desempenho

- Warm Performance / Signal Spark, mesmos tokens/superfícies, nomes e biblioteca; não criar uma nova identidade ou biblioteca de componentes.
- PT-BR e EN, claro/escuro, compacto/Pro Max, orientação suportada e Dynamic Type até Accessibility XXXL.
- VoiceOver: ordem de leitura, título/etapa compreensíveis, foco transferido ao abrir/mudar/fechar, controles nomeados, saída acessível; Large Content Viewer quando aplicável.
- Alvos ≥44 pt; conteúdo longo rolável sem cortar ações; não depender só de cor, movimento, blur ou haptic.
- Respeitar Reduce Motion, Reduce Transparency, contraste aumentado, diferenciação sem cor, energia/térmica. Movimento curto e cancelável sem duração mínima.
- Não acrescentar consultas de rede para montar o tutorial, nem bloquear restauração de sessão/Hoje. Sem sons, partículas/parallax/dependências novas.

## Critérios de aceite e regressão

1. Primeira sessão elegível oferece tutorial uma vez conforme estado escolhido; onboarding pendente/sem sessão/expirada não é contornado.
2. Próximo/Voltar/Agora não/Concluir funcionam; reabrir no Perfil funciona; comportamento após relaunch e interrupção é determinístico.
3. QA A→B→A, logout durante apresentação e callback tardio preservam isolamento.
4. Deep link, sheet/form em edição, resposta Flow em curso e alternância de abas não perdem dados nem causam duas apresentações.
5. Nenhum passo confirma registro, ativa plano, faz chamada paga, publica conteúdo ou solicita permissões por conta própria.
6. Texto corresponde às capacidades atuais e distingue proposta/revisão/confirmação; Biblioteca vazia não promete publicações nem mostra rascunhos.
7. Matriz visual/AX e teclado validados, incluindo VoiceOver real quando disponível; fallback18 compilado/testado deterministicamente sem alegar runtime18 físico.
8. Focados de estado/navigation/isolamento e UI dos passos; todo bug encontrado vira cenário exato, revisão independente para correções graves.
9. Repetir abertura/primeira tela utilizável com tutorial elegível versus já encerrado nas mesmas condições; nenhuma animação impõe espera. Regressão reproduzível bloqueia o efeito correspondente.
10. Build, scanner/localização, Analyze/Release/assinatura e suíte integral no **candidato que contém o tutorial**; smoke por cima do staging, rollback preservado.

## Encerramento

Adicionar resultado do tutorial ao relatório de 15 itens, incluindo textos/rotas cobertos, evidências e limites. O tutorial é a última implementação funcional; **a validação final vem depois dele**. Nenhum aceite editorial ou visual pode ser marcado em nome de Eduardo/Roberto.
