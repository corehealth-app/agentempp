# Intenção de conclusão do cadastro — preparação dormente

A fundação SQL e a integração HTTP estão implementadas localmente, desligadas
por padrão. Existe a rota `/onboarding/completion-intent`, com espelho no BFF;
o app distribuído e o escritor legado permanecem os mesmos. A integração iOS
e o QA HTTP real exigem seus próprios testes antes de ativar a configuração.

## Por que preservar a intenção original

Observar o epoch corrente a cada tentativa de concluir permite que uma
tentativa nunca admitida antes de um reinício adquira a autoridade nova. A
decisão entre legado e versionado também não pode depender da configuração no
momento do retry: uma mudança OFF/ON não muda a origem daquela tentativa.

O recibo positivo registra, antes da preparação assíncrona, o dono, um UUID de
preparação Q, o ID da intenção, uma chave emitida pelo servidor, o epoch E0 e o
instante UTC com seis casas. A tabela privada tem chave primária `(user_id,
preparation_id)` e unicidade por dono/ID e dono/chave. Sua FK aponta somente
para `authority.user_id`; E0 é copiado, sem FK para o epoch corrente. Assim o
reset pode girar a autoridade mantendo a tentativa antiga inválida.

## Componentes internos

A migration `20261021135320_mobile_signup_completion_intents.sql` adiciona três
RPCs, executáveis apenas pelo backend confiável:

| RPC | Efeito |
| --- | --- |
| `begin_mobile_signup_completion_intent(owner, Q)` | Emite uma identidade positiva; repetir Q preserva a identidade literal ou recusa stale. |
| `resolve_mobile_signup_completion_intent(owner, Q)` | Consulta uma emissão incerta; não cria epoch, recibo nem admissão. |
| `verify_mobile_signup_completion_intent(owner, ID, K)` | Verifica a identidade do dono e devolve E0 original para o bind posterior. |

Begin reaproveita a observação existente e mantém seus locks de transação:
workouts → usuário ativo → autoridade → intenção. As três RPCs exigem READ
COMMITTED. Resolve e verify não escrevem. A tabela tem RLS sem policies e
nenhum acesso direto por anon, authenticated ou service_role. Nenhuma RPC
conclui cadastro, registra consentimentos, concede acesso, abre lifecycle ou
cria metas/admissão de conteúdo.

O classificador puro `signup-completion-transport.ts` separa chaves legadas
genéricas da chave reservada `osc1:<uuid minúsculo>`, com metadata
`signup_strength_protocol` e `completion_intent_id`. Recusa tuplas incompletas,
versões desconhecidas, chaves reservadas sem metadata e payloads versionados
parciais sem `document_actions`. Considera a mesma normalização por trim do
validador legado antes de escolher o caminho. Remove somente esses dois campos
de transporte; documentos e confirmação de fotos continuam no input original.

## Integração HTTP local

O adapter concreto valida envelopes, dono/Q/ID/K e timestamp UTC de seis casas;
resolve não cria nada. A composição visível ao handler oferece intents e bind,
sem observe. Só transporte versionado constrói fontes; o legado não lê a flag.

O classificador roda antes da atualização parcial. Verify recupera E0 antes da
preparação assíncrona; bind recebe H original depois de fotos/elegibilidade.
OFF antes das fontes, depois de verify/preparação/bind, durante replay e depois
da preparação do acesso interrompe a operação antes do próximo efeito. Após
sucesso oficial SQL, nenhum novo OFF impede grant, finalização ou cleanup.

A nova rota POST recebe Q no JSON estrito e no cabeçalho; GET exige exatamente
um Q. Ambas usam autenticação e a isenção de entitlement já existente no
prefixo onboarding. OFF responde 503 antes das fontes. Pedidos despachados ON
podem devolver o recibo conhecido após OFF. O DTO público não inclui E0 ou
horário. Não há ledger HTTP, retry ou emissão automática em resolve.

`GET /onboarding` anuncia a capacidade somente ON e conserva os limites do DTO
e o cleanup existente. Contratos e erros estão em `docs/mobile/api-v1.md`.

## Integração que ainda falta

- Congelar no cliente rascunho, modo e Q antes de aguardar. Bloquear edição
  também durante a preparação e conservar a geração da sessão, inclusive A→B→A.
- Após emissão incerta, resolver Q por leitura, sem emitir outra chave
  automaticamente. Um 401 definitivo pode repetir o mesmo pedido após refresh.
- Testar o caminho completo, os replays, mudanças de configuração, reset durante
  a preparação e preservação de fotos/acesso/finalização antes da ativação.

O teste SQL usa somente o stack nativo local explicitamente guardado e os dois
donos sintéticos já existentes. Os cenários e resets ficam em transações com
ROLLBACK. Não é roteiro para staging nem prova de HTTP, concorrência ou iOS.
