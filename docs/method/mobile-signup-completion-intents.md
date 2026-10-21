# Intenção de conclusão do cadastro — preparação dormente

Os componentes deste documento ainda não são chamados pelo cadastro público.
Não há ativação por padrão, rota nova, alteração do app distribuído ou mudança
no escritor legado. A integração HTTP/iOS exige seus próprios testes antes de
ligar qualquer configuração.

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

## Integração que ainda falta

- Classificar antes do ramo de atualização parcial; uma tentativa versionada
  nunca pode cair no escritor legado, inclusive quando desligada.
- Verificar o recibo antes de preparar fotos/elegibilidade; passar E0 original
  ao bind atual depois da elegibilidade. O writer e o replay continuam conferindo
  a mesma autoridade. Uma recusa 422 não deve vincular H nem reclamar o cache HTTP.
- Congelar no cliente rascunho, modo e Q antes de aguardar. Bloquear edição
  também durante a preparação e conservar a geração da sessão, inclusive A→B→A.
- Após emissão incerta, resolver Q por leitura, sem emitir outra chave
  automaticamente. Um 401 definitivo pode repetir o mesmo pedido após refresh.
- Testar o caminho completo, os replays, mudanças de configuração, reset durante
  a preparação e preservação de fotos/acesso/finalização antes da ativação.

O teste SQL usa somente o stack nativo local explicitamente guardado e os dois
donos sintéticos já existentes. Os cenários e resets ficam em transações com
ROLLBACK. Não é roteiro para staging nem prova de HTTP, concorrência ou iOS.
