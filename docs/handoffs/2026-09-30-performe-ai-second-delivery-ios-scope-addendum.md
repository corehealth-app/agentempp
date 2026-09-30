# Addendum — segunda entrega revisada do Performe AI

**Data:** 2026-09-30  
**Decisão:** Eduardo definiu o escopo e a ordem da segunda entrega após o [addendum de 2026-09-14](2026-09-14-performe-ai-client-beta-flow-v1-addendum.md) e o [handoff beta de 2026-09-30](2026-09-30-performe-ai-beta-handoff-to-codex.md). O dossiê histórico permanece em `b4c09e80190fd6ce5c5f59b5193f8a6621554854:docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`.

Este addendum altera a **ordem da entrega comercial** a partir desta decisão. Não altera nem apaga os documentos, PDFs ou evidências anteriores.

## Escopo da segunda entrega

- Entregar um **candidato iOS funcional, navegável e testável em staging** para avaliação do Roberto, com as principais jornadas reais verificadas. Trata-se de Alpha/Beta interna, não da entrega final nem de publicação em loja.
- Performe AI é produto somente em **app iOS e Android**. Android continua no escopo global, mas fica para a **entrega final** e não bloqueia esta segunda entrega. Não iniciar implementação Android nesta operação.
- WhatsApp está **fora da superfície pública e dos critérios de aceite** do produto. Código legado e compartilhado permanece enquanto houver dependências; alterações nesses pacotes exigem análise de impacto e preservação do runtime existente. Esta decisão não autoriza mutação em Production.
- A Biblioteca faz parte do produto, mas sua validação funcional fica **por último** nesta sequência. Ela não bloqueia câmera, áudio, Flow, planos, Hoje, rotina, notificações, smoke integrado ou regressão iOS.
- Roberto é o responsável editorial e o publicador. Eduardo, como `nutrition_admin`, é o revisor independente. Nenhuma revisão ou publicação deve ser registrada em nome de outra pessoa.

## Ordem operacional vigente

1. Validar as jornadas físicas de câmera, microfone e plano por foto no iPhone de staging.
2. Fechar o smoke integrado das jornadas principais e os bugs visíveis que impedem a avaliação.
3. Executar a regressão iOS completa, incluindo acessibilidade, scanner de marca, build e assinatura.
4. Concluir o fluxo editorial real e o E2E da Biblioteca.
5. Solicitar o aceite visual explícito de Eduardo e classificar separadamente a prontidão técnica e o canal de distribuição para Roberto.

A **entrega final** continua responsável por Android, homologação final, distribuição/publicação, backoffice final e handover. Um app funcionando no iPhone de Eduardo não comprova que Roberto já consegue instalá-lo remotamente.

## Limites desta operação

Usar apenas staging e contas QA autorizadas. Não executar push, PR, merge, tag, deploy em Production, TestFlight, App Store, contratação ou criação de serviço pago persistente. Preservar o deployment histórico `dfik0mb7c`. O aceite visual só pode ser marcado após confirmação expressa de Eduardo.

**ANDROID STATUS:** `DEFERRED_TO_FINAL_DELIVERY`  
**WHATSAPP STATUS:** `OUT_OF_PRODUCT_SCOPE`  
**PRODUCTION STATUS:** `NOT DEPLOYED`
