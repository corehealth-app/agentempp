# Escolha inicial após cadastro sem protocolo — M3B

O cadastro concluído sem protocolo continua sem metas até uma escolha explícita permitida pela avaliação atual. Uma confirmação de saúde não atribui automaticamente uma fase. O cálculo autoritativo é do servidor; o app envia somente a opção e a referência opaca da prévia.

## Composição preparada

`createClinicalFirstPhaseRoutes` oferece três handlers autenticados, com entitlement normal, JSON limitado a 2 KiB e chaves UUID:

| Contrato | Entrada | Resposta pública |
| --- | --- | --- |
| GET `/api/mobile/v1/protocol/first-phase` | Sem parâmetros | Disponibilidade, opções, datas civis, campos ausentes e orientação profissional genérica |
| POST `/api/mobile/v1/protocol/first-phase/preview` | `Idempotency-Key` + `{ "phase": "recomposicao" }` | Prévia opaca, fase, data efetiva, validade e metas oficiais exibidas |
| POST `/api/mobile/v1/protocol/first-phase/confirm` | Outra chave estável + `{ "preview_id": "<UUID>", "phase": "recomposicao" }` | Confirmação opaca, fase e datas, sem alegar uma política atual |

**Esses handlers ainda não estão montados por arquivos `route.ts`.** A factory foi exercitada com os serviços reais e RPCs SQL no transporte local de rollback. Nenhum endpoint novo foi publicado. A montagem e a ativação devem acompanhar a conclusão do cadastroV2, FULL, fotos, leitores nativos e dois consumidores do Flow; o candidato clínico incompleto não é publicado.

As projeções públicas excluem idade, IMC, respostas de saúde, percentual/origem usado na fórmula, user/generation/epoch/context hashes, episódio e snapshot. O serviço e SQL possuem a autoridade de idempotência; não há outro claim HTTP que substitua seu recibo original. Repetições são resolvidas antes de capturar/recalcular o estado atual.

## Cliente nativo preparado

`ClinicalFirstPhaseModel` controla opções → prévia → confirmação. `ClinicalFirstPhaseView` mostra as metas recebidas e exige confirmação explícita; o cliente não calcula elegibilidade, calorias ou proteína. Uma confirmação sem resposta conserva a mesma intenção/chave e impede trocar a escolha enquanto o resultado for incerto. Fechar a folha mantém essa intenção no modelo da sessão.

`MobileClinicalFirstPhaseRepository.scoped(for:)` usa o sujeito Auth original da shell, que é diferente do ID interno do paciente. A cópia do transporte conserva esse owner/generation; operações validam a lease antes/depois, registram trabalho cancelável e publicam sob o gate visível da sessão. Um vínculo antigo não pode se vincular novamente a B ou a uma nova sessão A.

`AppDependencies.clinicalFirstPhase` permanece `nil` por padrão. A capacidade injetada aparece em **Perfil → Seu objetivo** apenas quando a política oficial informa `phase_selection_pending`. Esse estado não é mais confundido com uma tela vazia. A confirmação solicita atualização de Hoje, Plano, Progresso e Objetivo; o recibo histórico não restaura metas nem remove risco posterior.

## Qualificação ainda necessária

- Montagem das rotas e composição conjunta dos leitores `currentV1`, cadastroV2, FULL, Flow e fotos.
- QA conectado da navegação/renderização, erro/conflito, sessão e refresh; modelos/repository/build local não substituem esse QA.
- Fotos recorrentes reais, três novas por REGULAR, quota e descarte antes da ativação.
- T4/T5, revisão final do plano completo e entrega integrada via TestFlight.
