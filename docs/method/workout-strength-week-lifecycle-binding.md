# Vínculo entre geração semanal e lifecycle de treino

## Papel e limites

`private.strength_week_lifecycle_bindings` registra a prova conjunta de uma
geração Y do cadastro e de um lifecycle real de treino. Os dois UUIDs têm
identidades diferentes. O vínculo não cria treinos, denominadores, planos,
fontes de ausência ou histórico retroativo; também não conta treinos.

Migration: `20261020180000_mobile_strength_week_lifecycle_binding.sql`.
O único corpo existente alterado é
`public.confirm_mobile_workout_registration`: um `PERFORM` após a confirmação
da admission e do pending, dentro do bloco transacional S17D. Removendo esse
`PERFORM`, o corpo é idêntico ao da migration `20261015170000`.
Assinatura, resultado público, replay e ACL da confirmação são preservados.
Nenhum core compartilhado ou caller legado de WhatsApp é alterado.

## Criação e reutilização

O helper privado `bind_mobile_strength_week_lifecycle(owner, admission, lifecycle)`
exige o backend confiável e READ COMMITTED. O resolver real precisa comprovar a
captura da nova confirmação. A geração aberta deve vir do receipt `first_fresh`
do mesmo owner/epoch; a source referenciada deve ser a frequência informada
original, com os mesmos identificadores de operação e clocks ordenados.

O lifecycle deve estar aberto, ser o pointer corrente e ter sido aberto depois
ou no instante de abertura de Y. Sem essa prova, a confirmação continua válida
e o acompanhamento fica indisponível. Um lifecycle anterior a Y não autoriza
adoção de seus fatos antigos. O cadastro não inicializa Flow para criar prova.

Na primeira confirmação elegível, o helper grava admission, revisão, source,
receipt e um `bound_at` obtido por `clock_timestamp()` depois das esperas e
validações. Uma confirmação posterior da mesma geração/lifecycle valida sua
própria captura e reutiliza a origem e o relógio do primeiro vínculo.
Replay da confirmação retorna antes do helper: nunca cria ou repara vínculo.

Locks seguem a ordem S17D: catálogo → advisory workouts → users NO KEY UPDATE
→ epoch → admission → pending → lifecycle → scope Y → binding. As aquisições
anteriores a Y são reentrantes sob S17D. Nenhum advisory de onboarding ou
promoção do lock de users é introduzido pelo helper.

## Leitura e vigência

RPC somente para backend:

```text
get_mobile_strength_week_lifecycle_binding(owner, expectedGeneration, expectedLifecycle)
  → { status: "ready", proof }
  | { status: "unavailable", reason: "binding_unproved" }
```

`proof` tem exatamente: `ownerID`, `generation`, `epoch`, `lifecycleKey`,
`signupAdmissionID`, `frequencySourceVersionID`, `workoutAdmissionID`,
`workoutContentRevision` e `boundAt` (UTC com seis casas decimais).
O consumidor futuro deve obter owner e identidades do contexto confiável;
esta RPC não é uma rota HTTP pública nem uma autorização derivada de texto.

O leitor revalida epoch/pointer, lifecycle e Y abertos e os recibos originais.
Ele usa a operação durável de captura; não exige log, fato ou pending antigo
vivos. Excluir legitimamente o treino original não apaga a associação entre
geração e lifecycle. Isso não mantém o treino excluído na contagem: o futuro
contador ainda deve usar suas fontes oficiais de fatos elegíveis.

Reset fecha Y e lifecycle e gira epoch. O binding histórico é conservado e
deixa de ser elegível. Identidade esperada antiga ou prova ausente devolve
indisponibilidade. Binding corrente com origem contraditória levanta `XX001`;
não há reparo por leitura nem substituição silenciosa. Erros operacionais
propagam. Input inválido: `22023`; backend não confiável: `42501`; conta
ausente/inativa: `P0002`; isolamento diferente de RC: `22023`.

## Proteção e atomicidade

Tabela privada, RLS, FKs compostas por owner e sem DML concedido aos papéis
de cliente ou service_role. Binding imutável em UPDATE. Helper executável
somente pelo owner; leitor executável por owner e service_role. Não há FK
para log/fato/pending vivo nem para o epoch corrente mutável.

A migração verifica corpo, linguagem, owner, configuração e ACL antiga da
confirmação antes de substituí-la. Drift ou objeto novo desconhecido interrompe
a migração. Falha após inserir o vínculo desfaz também captura, pointer,
admission e pending; o teste compara todas as linhas do owner antes/depois.

## Evidência local de 20/10/2026

- RED causal: cadastro keyed e S17D reais passaram; controle QA demonstrou
  reader funcional; removido o controle, a ausência do produtor gerou somente
  `P0001/C59BRIDGE_EXPECTED_OWNED_PROOF`.
- GREEN: `supabase/tests/mobile_strength_week_lifecycle_binding.sql` e fixture
  própria cobrem criação automática, segundo treino, replay sem refresh/reparo,
  exclusão do log original e nova confirmação, ausência de Y, lifecycle anterior,
  ACL/guard/identidades, imutabilidade, corrupção corrente, erro posterior com
  rollback integral e retry, reset e ausência de fontes/Flow inventados.
- Uma execução local em PostgreSQL17.11, 20 notices ordenados, 17 comandos
  com exit0, rollback externo e fingerprints dos quatro bancos. Só os três
  nextvals naturais persistem; schemas, funções e dados da tentativa revertem.
- 116 testes dos seis arquivos `workout-registration-*.test.ts` passaram.

Essas evidências são de execução nativa local em transação desfeita. Não
comprovam COMMIT/replay entre conexões, corrida concorrente do bridge, crash,
HTTP com banco integrado, iOS ou ativação remota. O novo SQL permanece local.
Fonte real de plano com validade finita, composição semanal, Hoje e iOS são
etapas seguintes de M3A; o vínculo sozinho não encerra esse marco.
