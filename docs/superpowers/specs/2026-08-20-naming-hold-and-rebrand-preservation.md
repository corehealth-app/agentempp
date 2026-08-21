# Naming Hold and Rebrand Preservation

## 1. Status e decisão

O nome público definitivo do produto está pendente. **Better Ahead** é somente
um candidato provisório. Não existe clearance jurídico formal confirmado.

Esta decisão substitui apenas a afirmação anterior de que Better Ahead era
nome final aprovado. Ela não revoga automaticamente Flow, não altera contratos
técnicos e não autoriza a substituição por outro nome.

## 2. Escopo congelado

Ficam congelados:

- Tasks 3–10 do rebrand iOS;
- render Better Ahead;
- Docker/renderer/captura de environment de assets;
- novos wordmarks, splash, AppIcon, identidade visual ou review PNG;
- nova copy pública Better Ahead;
- propagação pública de Flow;
- Workstream 2 somente onde a tarefa for branding/copy pública;
- metadata de loja, distribuição externa e submissão.

Valores Better Ahead já commitados na Task 2 podem permanecer no código como
estado provisório. Eles não representam clearance, decisão final, autorização
de lançamento nem razão para expandir a marca.

## 3. Escopo autorizado durante o hold

Pode avançar, sem depender do nome:

- contratos Mobile API;
- segurança de backend;
- staging;
- transporte HTTP autenticado;
- abstração de sessão/token;
- adapters técnicos;
- testes de contrato;
- infraestrutura de observabilidade e redaction;
- worktree nova e limpa para integração técnica, após gates próprios.

Todo novo código deve depender de interfaces semânticas de identidade quando
precisar de nome público. Não deve hard-codear Better Ahead, Flow ou outro
candidato. Features técnicas sem superfície pública não devem introduzir copy de
marca.

## 4. Identificadores técnicos preservados

Permanecem inalterados:

- target, scheme, módulo e source root `BodyFlow`;
- bundle ID `com.bodyflow.app`;
- contratos de API;
- payloads;
- chaves persistidas;
- telemetry events;
- accessibility identifiers;
- tipos, enums e valores de wire não públicos.

O hold não autoriza renomear internals por estética nem reverter commits da
Task 2.

## 5. Tratamento de Flow

Flow não foi revogado. Contudo, não deve ser propagado para superfícies
públicas novas enquanto o naming do produto estiver pendente. Integração
técnica pode manter uma interface semântica de guia/agente, sem criar novas
strings públicas de marca.

## 6. Preservação da worktree órfã

O path `/private/tmp/better-ahead-ios.GQgTa0/worktree` é evidência forense,
classificado `PHYSICALLY_INCOMPLETE_WORKTREE`. Não é uma worktree operacional.

É proibido:

- `git worktree prune`;
- reparar, remover ou editar
  `/Users/eduardohenrique/Developer/bodyflow/.git/worktrees/worktree1`;
- sobrescrever o path antigo;
- stagear as 1.420 deleções que aparecem pela metadata órfã;
- reconstruir por aproximação qualquer um dos seis blobs dirty ausentes;
- recriar ou rerodar o log RED;
- declarar a Task 3 recuperada;
- executar renderer, Docker, pnpm de marca ou nova renderização.

O único blob dirty preservado no object database é o teste registrado na
evidência física. Os demais seis bytes não possuem recuperação comprovada.

## 7. Reentrada futura do rebrand

A Task 3 só poderá ser reconsiderada mediante nova autorização explícita. Se os
bytes históricos não forem recuperados com proveniência verificável, a
reentrada exigirá:

1. baseline nova e documentada;
2. nova classificação de risco para os artifacts;
3. novo plano de renderer sem reaproveitar hashes como conteúdo;
4. nova aprovação para qualquer render;
5. revisão independente dos impactos de segurança e invariância.

Nenhum desses passos é autorizado por este documento.

## 8. Separação de ambientes

| Ambiente | Responsabilidade permitida |
| --- | --- |
| VPS | documentação, contratos, backend, segurança, staging e validação não nativa |
| Mac | Swift/SwiftUI, Xcode, simulador, testes nativos, acessibilidade e inspeção visual |
| Worktree órfã em `/private/tmp` | somente evidência física read-only |

A VPS não pode alegar execução de Xcode. A nova worktree de integração, se
criada futuramente no Mac, deve ficar em path durável fora de `/private/tmp`.

## 9. Limites externos

Este hold não autoriza produção, TestFlight, App Store, APNs, StoreKit,
RevenueCat, credenciais, push, migração, deploy, push Git, PR, merge ou
submissão de loja.
