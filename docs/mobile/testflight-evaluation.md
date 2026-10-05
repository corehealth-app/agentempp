# TestFlight de avaliação (staging) — preparação

Estado em 2026-10-05, sobre `64a0e71`. **Nada foi enviado à Apple.** Este
documento descreve o que já está pronto no projeto, como gerar o arquivo e o
que o Eduardo precisa fazer quando a Apple aprovar a conta paga.

## 1. Decisões do Eduardo (2026-10-05)

Decididas pelo Eduardo na sessão de trabalho de 2026-10-05, por respostas
clicadas a três perguntas (testadores, identificador, envio). Elas substituem,
só para esta avaliação fechada, a regra dos handoffs anteriores ("sem
TestFlight/App Store").

1. **Canal:** TestFlight com testadores **internos** (sem revisão beta da Apple).
2. **Identificador:** manter o provisório que já está no iPhone dele,
   `com.performeai.app.dev.k6942zjtv6`. O definitivo fica livre para a futura
   empresa.
3. **Envio:** liberado só depois que a Apple aprovar a conta, apontando para o
   **staging**. Até lá vale a regra dos handoffs: sem TestFlight/App Store.

A identidade técnica interna continua BodyFlow (alvo, esquema, módulo e o
padrão `com.bodyflow.app`). Nada foi renomeado.

## 2. O que mudou no projeto

| Item | Onde | Efeito |
| --- | --- | --- |
| Identificador só do app | `BodyFlow.xcodeproj`, alvo BodyFlow (Debug e Release): `PRODUCT_BUNDLE_IDENTIFIER = $(PERFORME_APP_BUNDLE_IDENTIFIER)`, padrão `com.bodyflow.app` | Simulador, testes e scanner continuam em `com.bodyflow.app`. O build de aparelho passa `PERFORME_APP_BUNDLE_IDENTIFIER=…` e só o app muda. |
| Manifesto de privacidade | `BodyFlow/PrivacyInfo.xcprivacy` | Sem rastreamento; declara `UserDefaults` com o motivo `CA92.1`. |
| Criptografia | `BodyFlow/Resources/Info.plist`: `ITSAppUsesNonExemptEncryption = false` | O esperado é evitar a pergunta de exportação a cada build (não testado: ainda não houve envio). |

**Por que o identificador mudou de lugar.** O comando antigo passava
`PRODUCT_BUNDLE_IDENTIFIER=…` na linha de comando, e isso valia para todos os
alvos: o pacote de recursos do swift-crypto saía com o mesmo identificador do
app. Em instalação direta passa; no envio é o erro conhecido de identificador
repetido (ITMS-90685; muito provável, nunca testado por envio). **Não use mais
`PRODUCT_BUNDLE_IDENTIFIER=` na linha de comando.**

**Base das duas declarações.**

- `UserDefaults` no código do app: `Core/Tutorial/GuidedTutorialStore.swift:28-41`,
  `Core/Reminders/LocalReminderRouting.swift:104-108`,
  `Core/Reminders/LocalReminderScheduler.swift:254-256`,
  `Core/Appearance/BodyFlowAppearance.swift:77-83` (modo de aparência). Datas de arquivo,
  tempo desde a inicialização, espaço em disco e teclados ativos não são usados
  (o binário só referencia `NSUserDefaults` entre as APIs com motivo).
- Criptografia: só HTTPS/TLS do sistema, Keychain, SHA-256 do CryptoKit
  (`Core/Reminders/LocalReminderPlanner.swift:82`) e, no pacote de login da
  Supabase, SHA-256 (PKCE) e verificação de assinatura RSA pelo sistema. Nenhum
  algoritmo próprio; o binário não carrega BoringSSL. A declaração é do
  Eduardo: se ele discordar, a chave sai.

## 3. Como gerar o arquivo

Script fora do repositório (uma fila só de Xcode; não envia nada):

```sh
~/.local/share/performe-ai/final-polish-20261001/handoff-20261004/testflight-archive.sh <numero-do-build>
```

Por dentro:

```sh
xcodebuild archive -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow \
  -configuration Release -destination generic/platform=iOS \
  -archivePath <saida>.xcarchive -xcconfig <xcconfig privado de staging> \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=K6942ZJTV6 \
  PERFORME_APP_BUNDLE_IDENTIFIER=com.performeai.app.dev.k6942zjtv6 \
  CURRENT_PROJECT_VERSION=<numero-do-build>
```

Depois o script confere o arquivo: os três valores privados presentes e no
staging (imprime só os hosts, nunca a chave), identificadores sem repetição,
manifesto de privacidade, chave de criptografia e assinatura. O build de
aparelho para instalar direto usa os mesmos ajustes com `build` no lugar de
`archive`.

**Número do build.** O projeto continua com `1`; o número vem do argumento.
Cada envio da versão 1.0 precisa de um número maior que o anterior. No envio
pelo Xcode o esperado é que a opção de gerenciar versão e build corrija isso
sozinha (não testado: ainda não houve envio).

## 4. O que o Eduardo faz depois que a Apple aprovar

Todo comportamento da Apple descrito neste documento vem do conhecimento da
documentação dela; nada foi exercitado, porque ainda não existe conta paga nem
envio. Em 2026-10-05 a inscrição estava parada na verificação de identidade
(pedido feito em 02/10; documentos enviados e em análise).

1. Conferir em developer.apple.com (Membership) se o Team ID continua
   `K6942ZJTV6`. Se mudou, avisar antes de qualquer build.
2. No Xcode, Settings > Accounts: o Apple ID dele conectado. O arquivo com
   `-allowProvisioningUpdates` e o envio usam **a sessão dele** para registrar
   o identificador e criar os perfis na conta dele. Precisa ser no Mac dele,
   com ele conectado.
3. Rodar o script com um número de build novo e ver todas as linhas `OK`.
4. No App Store Connect, criar o app (Apps > + > New App): iOS, nome
   "Performe AI", idioma pt-BR, identificador `com.performeai.app.dev.k6942zjtv6`.
   O identificador só aparece na lista depois de registrado; se não aparecer,
   o passo 3 (ou o registro manual em Identifiers) vem antes.
5. Enviar: abrir o `.xcarchive` no Xcode (Organizer) > Distribute App >
   **TestFlight Internal Only**. A alternativa por linha de comando está
   comentada no fim do script.
6. Convidar as **duas** pessoas (Roberto e a esposa; o Eduardo é o terceiro
   participante e já é o dono): Users and Access > convidar cada uma com um
   papel. Elas viram **usuárias da equipe dele** no App Store Connect, precisam
   de **conta Apple própria**, aceitam esse convite primeiro e só então entram
   no grupo de teste interno (TestFlight > Internal Testing) e instalam pelo
   app TestFlight. O papel dá acesso real ao registro do app; qual é o de menor
   acesso ainda não foi confirmado.
7. No iPhone dele: como o identificador é o mesmo, o esperado é o TestFlight
   instalar por cima do build atual, preservando os dados. Não testado.

## 5. O que continua em aberto

- **Declaração de dados coletados.** `NSPrivacyCollectedDataTypes` ficou de
  fora do manifesto de propósito: é declaração de privacidade (tipos e
  finalidades) e precisa da revisão do Eduardo. Pelo que se conhece da
  documentação da Apple ela não é exigida para o teste interno (não testado).
- **Exclusão de conta dentro do app.** Não existe. Pelo que se conhece das
  regras da Apple, só é cobrada para testadores externos (revisão beta) ou App
  Store (não testado).
- **Quem assina como desenvolvedor.** A conta individual do Eduardo é
  provisória. Um app que só existiu no TestFlight pode não ser transferível
  para a futura empresa (regra da Apple citada de memória, não conferida).
- **Build "Internal Only" não vai para testadores externos**: exige novo envio.
- **Perfil de desenvolvimento atual vence em 2026-10-12**; o build instalado
  direto deixa de abrir nessa data.
- **Não verificável sem a conta paga:** se o nome "Performe AI" está livre; se
  o Xcode 27.0 é aceito para envio; o resultado real do envio.
- **Antes de convidar alguém** (parte do cadastro, deixada para o fim): criar
  uma conta nova pelo build Release no staging, conferir o acesso automático de
  avaliação e a entrega de e-mail; hoje só há avisos publicados em pt-BR.
