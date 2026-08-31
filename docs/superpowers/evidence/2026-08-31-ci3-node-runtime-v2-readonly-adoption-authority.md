# CI-3 — authority para adoção read-only do Node capsule V2

## Classificação

- operação: `AUTHORIZE_READ_ONLY_ADOPTION_OF_EXISTING_NODE_CAPSULE_AND_RESUME_CI3_BRIDGE`;
- architecture: `READ_ONLY_NODE_RUNTIME_CAPSULE_V2_ADOPTION_VERIFIER_V1`;
- authority de criação preservada: `b08e6326fbd22c96b852ccfe53abdeb254e54bd1`;
- STOP terminal preservado: `030aa2be4e2facc5edbcda143c18a8477e727855`;
- tentativa de criação V2: `1/1_CONSUMED`, sem retry;
- tentativa de adoção read-only: `0/1` antes da publicação desta authority;
- tentativa da bridge: `0/1`.

## Estado físico observado read-only

O capsule publicado está fisicamente completo: claim original, capture de
closure, receipt do probe já concluído, Node final, runtime receipt e diretório
final existem com owner/mode/nlink esperados. Node, runtime receipt e diretório
final têm immutable flag real. O runtime receipt tem SHA-256
`577fff150c608bfa848c7e9775e92cd02ed427a83484e859480b3e2607a94744` e o
Node tem SHA-256
`6295488653f0d93b0a157841746fef7e72cc4328cfb60c4bbe0ca2668a836ffd`.

A closure foi revalidada somente pelo capture durável, sem nova descoberta:
7 entradas, 7 atravessando symlink, 0 sem symlink, 2 componentes finais
symlink, 5 finais regulares/intermediate-only, 9 hops totais, máximo 2, 7
targets canônicos e zero duplicatas. Os hashes permanecem:

- path list: `3f971424eee62e6754e5a82b7b5263fd0da4c76b2c5d7decd600f6b38e3da1cd`;
- manifest: `0ea781ac6ad63e50a38756f6e9b61978b91d81a6599f65007a9d0bea0e4f2210`;
- content set: `cd118bd931b067611e20fe85400a94b8668ef3773d12c2802cb5cc0cb391d9da`.

Nenhuma library path bruta é publicada por esta evidence.

## Causa raiz do STOP anterior

No modo de verify do builder V2, a expressão de binding do capability probe
aplica primeiro `JSON.stringify` a uma arrow function e tenta invocar a string
resultante. A precedência efetiva é um `CallExpression` cujo callee é o retorno
de `JSON.stringify`, e não a projeção do probe. A reprodução sintética mínima
gera o `TypeError` esperado, com zero filesystem real, zero secret e zero
processo externo. O erro ocorre depois da publicação física; não existe
mutation pendente que justifique recriação ou cleanup.

## Authority sucessora

O verifier-only novo fica em path Git novo. Builder V2, teste V2 e bridge
permanecem inalterados. Seus únicos modos públicos são `--self-test` e
`--verify-existing`; não há `--create` nem argumento adicional.

O protocolo autorizado é:

1. confirmar authority e snapshot Git-blob do verifier;
2. publicar claim de adoção fora do capsule por O_EXCL/O_NOFOLLOW e fsync;
3. reabrir claim/capture/probe/runtime receipt/Node com no-follow e identidade
   estável;
4. revalidar a closure exclusivamente a partir do capture;
5. conferir bytes source/capsule, owner, mode, nlink, hashes e flags imutáveis;
6. executar version/core smoke bounded;
7. executar fases bootstrap e self-hosted receipt-bound, sem segundo claim;
8. confirmar zero alteração nos artifacts e somente então publicar o receipt
   de adoção externo, root-only, `0444` e version-addressed.

O receipt liga authority/verifier, authority/builder antigo, STOP, todos os
artifacts e identities, closure, smokes e invariantes de preservação. Seus
controles obrigatórios são: zero rede, package manager e secrets;
`create=false`, `ldd=false`, `probe=false`, `chattr=false`,
`capsule_mutation=false`, valores/paths brutos falsos.

## TDD e gates antes da publicação

O RED inicial foi a ausência do verifier, mantendo a reprodução exata do bug
antigo. O GREEN usa somente fixtures sintéticas e exige pelo menos 120 casos,
zero fail/skip/todo e zero efeitos reais. Sintaxe, self-test, allowlist exata de
sete paths, `git diff --check`, preservação dos builders/componentes e duas
revisões com zero Critical/Important são gates anteriores ao commit.

## Continuação condicionada

Somente uma adoção read-only PASS autoriza a única tentativa ainda não
consumida da bridge `ba8473799a19aec586b0fe706bb7d4084589c86c`. O generator
continua vindo de seu blob publicado e roda exclusivamente pelo capsule
adotado. Esta authority não executa Mac, simulador, CI-3 Task 2, CI-4, cleanup,
Supabase, Vercel, banco, primary/live ou produção.

## Resultado terminal pós-authority

- verifier authority publicada:
  `461a2e0dbe091a5c352d5dfdc1952b444f41aac0`;
- testes do verifier: `155/155`, self-test `8/8`;
- adoção read-only: `PASS`, tentativa `1/1`;
- adoption receipt SHA-256:
  `1cd3843745c3bfa759d3e99f15a92651a8462610089bfb31175fba49b58ec0d3`;
- capsule original alterado: `NO`;
- generator bridge: blob/hash exatos, testes `154/154`, self-test `8/8`;
- bridge `--create`: tentativa `1/1`, `ERROR GIT_AUTHORITY`;
- claim/generation/config/receipt da bridge: ausentes.

O STOP da bridge ocorreu antes de qualquer source-secret read ou publicação.
O `gitResult` do generator publicado define `maxBuffer=64 KiB`; sua primeira
leitura autoritativa de blob tenta receber o próprio generator, com 82.675
bytes. O subprocesso excede o buffer e é classificado fail-closed como
`GIT_AUTHORITY`. HEAD, parent, tree, subject e a lista de 13 paths estavam
corretos; a worktree detached permaneceu limpa.

A tentativa não pode ser repetida. Uma continuação futura precisa publicar
authority sucessora que corrija explicitamente o bound do reader Git, cubra
blobs autoritativos acima de 64 KiB e conceda novo budget da bridge. O capsule
já adotado deve ser reutilizado read-only. Nenhum valor de configuração,
credential, origin, library path, token, PII ou service role é registrado aqui.
