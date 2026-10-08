# Flow — catálogo e seletor de frases C5

Peça local de servidor, ainda sem consumidor ativado. Não altera WhatsApp,
rotas, banco, cálculos ou telas. Não comprova os protocolos completos nem
aceite clínico, fidelidade integral aos PDFs ou QA no staging.

## Fonte e proveniência

Nove cópias byte a byte de `scripts/data/curated-phrases-*.json` estão em
`packages/agent/src/data/flow-curated-phrases/`. O runtime usa imports estáticos,
sem ler filesystem externo ou executar o CLI de ingestão. Fonte, hash, texto,
gatilhos e posição ficam preservados no catálogo congelado.

São 200 incentivos e 1.321 entradas alimentares (1.262 strings únicas),
27 blocos e 214 gatilhos normalizados. `phase-c2` está incluída; fases de
extração não são protocolos. Os IDs identificam endereço de origem dentro
da versão, por exemplo `food:c2:bom_verduras:007`. Uma nova fonte exige revisão,
fingerprint e versão correspondentes; não inferir estabilidade de índices
depois de editar a fonte. A versão inclui o hash do manifesto ordenado das
nove fontes. Os testes conferem cópias, hashes e todas as entradas contra
os JSON originais. Isso não prova transcrição integral dos PDFs.

## Seleção pura

`selectFlowCuratedPhrase` recebe usuário, evento, locale, contexto e estado;
devolve seleção e próximo estado. Não usa relógio, aleatoriedade, LLM,
embeddings, Supabase, RPC, ingestão ou cache global por pessoa.

- Idioma: somente `pt-BR`/`pt`, aceitando caixa e espaços externos. Idioma
  ausente ou não coberto devolve vazio; nenhuma tradução é inventada.
- Alimento: preserva a fórmula existente de âncora e desempate pela ordem.
  Valida nomes/macros finitos e não negativos, incluindo overflow do peso
  derivado. Só usa gatilhos exatos após caixa/acentos/espaços; não pluraliza,
  faz match semântico ou troca ingrediente principal por secundário coberto.
- Horário: restrição explícita por ID e guarda temporal existente. `outro`
  exige compatibilidade com os cinco horários. Horário ausente/inválido falha.
  Não relaxa filtro quando nenhuma frase cabe.
- Incentivo: contexto genérico aceita fontes `any`/`continuity`; manhã inclui
  `morning`. Treino aceita também incentivos `workout`, com motivo de fallback;
  isso não equivale a biblioteca específica de exercício.
- Placeholder: só `{alimento}`, com âncora validada e substituição literal.
  Variável desconhecida ou âncora ausente exclui candidato. A fonte fica intacta.
- Texto público: projeção comum de nomes e guarda de tom existentes, sem
  reescrever frase pela preferência Focus/Impulse/Zen. Dedupe pelo texto final,
  inclusive duplicatas entre fases/IDs ou após projeção.

Motivos são técnicos, não copy pública: `selected_food`, `selected_incentive`,
`workout_incentive_fallback`, `unsupported_language`, `invalid_input`,
`invalid_state`, `state_owner_mismatch`, `catalog_version_mismatch`,
`event_key_conflict`, `no_anchor`, `no_food_match`, `no_eligible_phrase`,
`only_previous_phrase`, `rotation_exhausted`.

## Estado, repetição e replay

`createFlowPhraseRotationState` exige usuário e versão. O estado contém ordinal,
chave do último texto, textos usados no ciclo e receipts por evento. Estado
inválido, de outra pessoa ou versão retorna vazio sem reset. Não muta entrada,
estado ou catálogo. Mapas são objetos simples; eventos não usam propriedades
herdadas (`__proto__` também é uma chave própria válida).

Ordena por ID, deduplica o texto final, exclui a anterior e escolhe entre as
frases ainda não usadas com seed do usuário/ordinal. Ao esgotar o ciclo,
reinicia o conjunto usado mantendo a exclusão da anterior. Se só restar a
anterior, retorna vazio. Ordinal só avança na seleção nova bem-sucedida.
No teto `Number.MAX_SAFE_INTEGER`, o estado continua válido para replay;
novos eventos recebem vazio `rotation_exhausted`, sem incremento inseguro.

Eventos válidos guardam fingerprint e seleção, inclusive vazia. Mesmo evento
e payload devolvem a seleção original sem avançar nem regredir o estado
corrente, inclusive após outros eventos. Payload diferente é conflito.
Pedidos/estados inválidos não consomem evento. Esses receipts são dados de
servidor confiáveis, não um mecanismo de autenticação de estado fornecido
pelo cliente.

Persistência, retenção, serialização e concorrência pertencem aos consumidores.
O mapa de receipts e o conjunto de textos podem crescer; não armazená-los
indefinidamente em cache global. Compactar só quando o ledger de idempotência
cobrir os eventos removidos. Duas chamadas com o mesmo estado não formam uma
sequência; o consumidor precisa atualizar o estado com exclusão/versão própria.

## Integrações seguintes

C7 status, C13 retorno do registro e C15/C16 avisos/“Ontem” integrarão essa peça
usando dados confirmados e eventos estáveis. Turno Flow já possui
`providerMessageId = mobile_flow/<user>/<Idempotency-Key>`; `request_id` e
timestamp da tentativa não são chaves de replay. Preservar o bypass existente
de replay antes de chamar o agente. Leituras/refrescos não devem consumir uma
nova frase como se fosse confirmação de visualização.

O histórico atual role/content não contém cursor/ID/ledger suficiente para
rodízio entre todas as superfícies. Essa integração ainda precisa implementação
e prova de persistência/isolamento. C17 possui suas dez variações próprias e
não depende deste catálogo; não substituir por incentivo genérico.

> RC C5 — cenário frase real “refeição prática” variante ID e texto ausentes dos nove JSON NÃO coberta nesta PR (pendência da audit 2026-10-08).

> RC C5 — cenário frase específica por exercício variante biblioteca não entregue NÃO coberta nesta PR; fallback usa somente incentivo existente (pendência da audit 2026-10-08).

> RC C5 — cenário rodízio entre sessões e superfícies reais variante estado persistente dos consumidores C7/C13/C15/C16 NÃO coberta pela peça local inerte (pendência da audit 2026-10-08).

A fixture mecânica `synthetic-slot-policy` testa somente a restrição de lanche;
não está no catálogo público. “Refeição praticamente” da fonte de verduras não
é a frase-alvo ausente. Não gerar frase nova para encerrar essas lacunas.
