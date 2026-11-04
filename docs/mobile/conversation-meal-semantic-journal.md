# Interpretação durável e recuperação de preparação

Este incremento é interno e inativo: não chama provedor, não ativa rota e não
autoriza consumo ou gravação de refeição. A reserva durável limita a permissão de
invocação; o adapter deve usar somente um `claimed` recebido depois do commit do
RPC e executar uma requisição física com retries desabilitados.

## Tentativa única

`start_conversation_meal_semantic_attempt(owner, command_id, interpreter_version,
expected_source_hash)` exige comando admitido, epoch atual e captura original
guardada. Somente uma nova tentativa valida fonte atual/dia civil aberto e retorna
`claimed` com UUID escolhido pelo banco. Não há parâmetro de UUID de tentativa
nesse RPC. Não se exige candidato opaco previamente anexado.

Epoch, input hash e source hash derivam da identidade/captura imutáveis do
comando. A versão atualmente admitida é `conversation.meal-interpreter.v1`;
clientes não escolhem outra versão para obter uma lane nova. Uma tentativa já
iniciada retorna `reconciliation_required`, mesmo após 24 horas ou fechamento do
dia. Não há TTL, lease, expiração ou reclaim. Resposta de start perdida exige
consulta; leitura nunca concede permissão para invocar o provedor.

As respostas com estado têm exatamente:

```text
action, owner_id, command_id, attempt_id, interpreter_version,
input_hash, source_hash, epoch, status, result, result_hash,
started_at, finished_at, error_code
```

`status` é `started`, `completed`, `unknown` ou `error`. Um resultado completo
possui `result` e `result_hash`; os outros estados mantêm ambos NULL. Erros usam
somente `provider_outcome_unknown` ou `provider_terminal_error`, sem prompt,
mensagem privada do provedor ou credencial. Timestamps são do banco, em UTC.

`read_conversation_meal_semantic_attempt(owner, command_id, interpreter_version)`
retorna `available` para resultado completo e `reconciliation_required` para os
outros estados. É STABLE, usa um snapshot e não inicializa, captura ou grava nada.

`commit_conversation_meal_semantic_result(owner, command_id, interpreter_version,
attempt_id, result)` conserva a resposta conhecida da tentativa original.
`mark_conversation_meal_semantic_unknown(..., attempt_id, error_code)` conserva
falha genérica/resultado incerto. O primeiro terminal vence; tentativas posteriores
com o mesmo UUID retornam `replay` antes de validar novo payload. UUID diferente
retorna `attempt_conflict` sem receber o resultado anterior. Fonte/dia atuais não
são recapturados no finish: uma resposta tardia ainda deve ser guardada, enquanto
o preparador de domínio possui seu próprio CAS de fonte atual.

## Resultado fechado, sem autoridade de domínio

`conversation.meal-interpretation.v1` guarda IDs/hashes/versão anexados pelo
backend, unidades capturadas, decisão/motivo, referências por ocorrência e
metadata técnica do provedor. Não admite nutrientes, alvo clínico ou
`complete_source`. O limite é 128 KiB de JSON canônico SQL, quatro unidades e
trinta foods. Partições e referências usam offsets UTF16, sem cortar surrogate
pairs; ordem das unidades e índices visuais corresponde à fonte original.
O significado de uma resposta positiva continua sob o parser semântico do backend.

`result_hash` é SHA256 do JSON compacto produzido por
`private.conversation_command_canonical`. É um token opaco do banco: a notação
numérica de `JSON.stringify` pode diferir, por exemplo, para custo `1e-8`.
Ter um resultado `completed` significa interpretação concluída, não refeição
gravada nem prova SQL de consumo.

## Recuperação de prepare/write com resposta desconhecida

`read_conversation_meal_prepared(owner, command_id)` retorna `absent`,
`stale_epoch`, `event_conflict` ou:

```text
{ action: available, command: <binding existente>,
  source: null | { source_hash, captured_at, context },
  resolved: null | { resolved_hash, prepared_at, resolved },
  receipt: null | <conversation.meal-effect.v1> }
```

Resolved exige source; receipt exige resolved e source. O snapshot valida dono,
epoch, DTO/hash original, captura/hash, preparação/hash e recibo factual original.
Retorna os payloads guardados, incluindo a preparação de até 256 KiB; nunca chama
calculador, consulta nutricional selada, captura clínica viva ou writer. Assim um
prepare já concluído não precisa recalcular e um write já concluído não se repete.
Uma edição C11 não reescreve esses fatos originais.

As tabelas privadas têm RLS e nenhum grant direto, inclusive para service_role;
somente os RPCs confiáveis têm EXECUTE. O cascade da captura/epoch apaga tentativas
e resultados. O tombstone do comando permanece e impede reacquirir o mesmo UUID
após reset; exclusão da conta continua cascading.
