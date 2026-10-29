# Assinaturas no iOS

A entrada fica em **Perfil → Assinatura** (`AppRoute.billingPlans`). Ela não
depende de Hoje, do registro de treino ou de o acesso já estar concedido.

## Autoridade e sessão

- `GET /api/mobile/v1/entitlements` é a fonte de `has_active_access`. Status,
  datas, cache do SDK e resultado da loja não substituem esse booleano.
- `BillingSessionSource` cria uma leaf própria no mesmo
  `MealRecordAuthenticationLifetime`. Ela captura o Auth lease original e o
  ticket de ativação antes das chamadas. Um novo login do mesmo usuário também
  precisa de outro ticket; `userID` sozinho não identifica a apresentação.
- O UUID para o RevenueCat vem de `/me.data.id`: é a chave de domínio do
  paciente, distinta do subject Auth. O transporte permanece no lease original.
- A revogação fecha imediatamente o fence. O encerramento aguarda o callback
  real do SDK, libera somente o grant original e finaliza o patient-work ID
  original, inclusive quando ele chega depois da revogação.

`BillingSDKCoordinator` usa o SDK oficial RevenueCat **5.99.2**, fixado no SPM.
O permit mantém configure/login/offers/purchase/restore/logout exclusivos
durante os awaits. Cancelar uma Task não significa que a operação do SDK acabou.
Um teardown antigo não pode deslogar o novo dono.

## Apresentação e compra

`BillingReadyContext` conserva um `BillingPlansModel` por contexto. Voltar e
reabrir a rota não apaga uma operação em andamento ou uma confirmação pendente.
O binding invalida esse modelo ao encerrar a sessão.

O acesso oficial é publicado antes de aguardar o catálogo. Ofertas usam título,
preço localizado e período fornecidos pelo SDK. Catálogo vazio ou com erro não
impede restaurar compras quando a configuração e o BFF permitem essa operação.

Uma seleção de catálogo autoriza uma tentativa de compra. Cancelamento final ou
erro pode renovar o catálogo, sem repetir a compra automaticamente. Após
`completed`, o modelo faz uma consulta de acesso. Resposta negativa ou falha
mantém a confirmação pendente. **Verificar confirmação** consulta somente o BFF;
não repete compra, restore ou ofertas. Uma interrupção de resultado incerto não
é apresentada como compra concluída.

`CustomerInfo`, delegates e streams do SDK não concedem acesso. O logout público
normal do SDK não prova a remoção de todos os seus caches; as proteções de sessão
continuam necessárias mesmo quando o SDK relata erro de logout.

## Configuração e qualificação

A chave pública Apple opcional é lida de
`Bundle.main.infoDictionary["PERFORME_REVENUECAT_PUBLIC_KEY"]`. Sua ausência
mantém o checkout indisponível e preserva a consulta oficial de acesso. Nenhuma
chave, preço, produto, trial ou benefício comercial deve ser inventado para
preencher essa configuração.

O `Info.plist` contém somente o port de build
`$(PERFORME_REVENUECAT_PUBLIC_KEY)`, sem valor padrão válido. Arquivar o app com
uma chave real exige fornecê-la explicitamente ao build depois da qualificação.

No servidor, a disponibilidade da compra usa
`MOBILE_REVENUECAT_BILLING_PROJECT_REF`, ausente por padrão. O valor deve ser um
único ref de projeto e corresponder exatamente à origem HTTPS canônica em
`NEXT_PUBLIC_SUPABASE_URL`; a produção legada é sempre recusada. A configuração
também exige ambiente, segredo de assinatura e mapa de produtos válidos do
webhook. O parser é compartilhado com o handler e lido a cada solicitação,
preservando os bytes do segredo. Somente `provider`, `available` e `reason` são
acrescentados à resposta pública. Essa disponibilidade não altera
`has_active_access` nem dispensa os guards HTTP 402.

O seletor do projeto é uma ativação operacional: deve continuar ausente até
concluir a qualificação abaixo. Configuração sintaticamente válida não prova
que a loja ou a entrega dos eventos funciona. O handler RevenueCat existe no
admin, mas o BFF móvel espelha somente as rotas móveis; o endpoint real do
webhook ainda precisa ser publicado e verificado no destino correto. Não
configure no provedor um endereço presumido do BFF.

A presença do código não comprova ativação comercial. Antes de ativar ou
distribuir uma versão com compras, qualificar projeto/chave/catálogo reais,
política de transferência de contas, webhook autenticado, capability IAP,
informações aprovadas da assinatura e compra/restauração/lifecycle em sandbox.
Conferir também os links públicos funcionais dos termos e da privacidade,
conforme as [orientações de assinaturas da Apple](https://developer.apple.com/app-store/subscriptions/).

## Evidência de desenvolvimento

As suítes `BillingSDKCoordinatorTests`, `BillingSessionBindingTests` e
`BillingPlansModelTests` cobrem ownership, autoridade BFF e reconciliação.
`BillingPlansUITests` percorre o Root/Perfil reais com Auth/lifecycle/transport e
binding reais, substituindo somente HTTP e SDK por respostas sintéticas locais.

`BillingUIFixture` e seus diagnósticos existem somente em `#if DEBUG`, exigem
`--ui-testing` e uma única seleção explícita. Seus preços e resultados sintéticos
não constituem teste de compra na App Store. O caminho Release não instala essa
fixture. Os testes de UI usam tema temporário em memória; a preferência de tema
do usuário real segue o armazenamento e o relógio já existentes.

Validar a versão distribuída e o aceite do cliente separadamente dos testes
locais. Não reutilizar um recibo de upload para afirmar que um código posterior
já foi distribuído.
