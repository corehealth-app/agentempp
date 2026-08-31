# CI-3 — authority V2 da closure Node canônica no-follow

**Dossiê:** 1.7.4
**Arquitetura:** `PRIVATE_VERSIONED_IMMUTABLE_NODE_RUNTIME_CAPSULE_V2`
**Algoritmo:** `NOFOLLOW_COMPONENT_CANONICALIZATION_V1`
**Estado:** `AUTHORITY_AUTHORED_RUNTIME_NOT_YET_CREATED`

## Ruling e baseline

V1 (`f039fe38...`) mantém sua tentativa 1/1 consumida, STOP pré-claim e
ausência de claim/probe/staging/capsule/receipt. O STOP `bd2ffd96...` e o
STOP_PRE_AUTHORITY seguinte permanecem válidos; não há retry, edit ou cleanup.

Duas observações independentes produziram 7 loader entries; 7
`traverses_any_symlink`; 0 `traverses_zero_symlink`; 2
`final_component_symlink`; 5 `final_component_regular`; 5
`intermediate_only_symlink`; 9 hops; máximo 2; 7 targets regulares canônicos;
zero duplicatas. Hashes: path-list
`3f971424eee62e6754e5a82b7b5263fd0da4c76b2c5d7decd600f6b38e3da1cd`,
manifest `0ea781ac6ad63e50a38756f6e9b61978b91d81a6599f65007a9d0bea0e4f2210`
e content-set
`cd118bd931b067611e20fe85400a94b8668ef3773d12c2802cb5cc0cb391d9da`.
Raw loader/canonical paths não são emitidos.

## Algoritmo, claim e recovery

O walk usa BigInt `lstat/readlink`, parents root-owned não graváveis por
group/other, target bounded, limite de 40 hops, ciclo/drift e abertura final
única `O_RDONLY|O_NOFOLLOW`, seguida de revalidação integral. Root comprometido
fica fora do threat claim; bibliotecas do SO não são chamadas de imutáveis.

Claim V2 root-only `0600`, O_EXCL/O_NOFOLLOW e fsync precede todo `ldd`
operacional. Capture root-only persiste manifests antes do probe. Claim sem
capture é STOP; claim+capture completo revalida sem novo source `ldd`; capture
sem claim ou divergente é rejeitado.

O probe persiste e fsynca seu receipt de tentativa antes de remover o arquivo
sintético, fechando a janela de repetição em crash. O capture e os JSONs de
estado são reabertos no mesmo fd `O_NOFOLLOW`, com lstat/fstat/read/fstat/lstat
estáveis. Na publicação, o Node final recebe `+i` antes da captura de sua
identidade física; somente então o receipt é criado como o último arquivo,
fsyncado e congelado, seguido pelo diretório final.

## Capsule, bridge e limites

Após authority remota, V2 recebe tentativa fresca 1/1. Node `0555`, receipt
`0444` e diretório `0555` terminam root-owned, single-link e imutáveis.
`/usr/bin/node` permanece bootstrap-only; NVM/packages não são usados. Bridge
authority `ba847...` roda somente após capsule PASS, sem copiar credential ou
emitir service role/valores. São exigidos 200+ testes, baseline real e duas
reviews 0C/0I. External systems, Mac, Task 2, CI-4 e cleanup continuam
proibidos; deadline da fixture `2026-09-11T11:44:11.182Z`.

## Gates e reviews da authority

O gate final executou syntax check, `264/264` testes, zero falhas, skips e
todos, self-test `8/8`, zero rede, zero `chattr` real nos testes e zero leitura
de input secreto. Duas reproduções read-only adicionais confirmaram todas as
onze dimensões e os três hashes sem emitir paths.

Review A cobriu parser `ldd`, symlinks intermediários/finais, trust de parents,
limites/ciclos, descriptor no-follow, drift, manifests, equivalência e ordem
receipt-last: `0 Critical / 0 Important`. Review B cobriu V1 byte-idêntica,
STOP e budget, claim/capture/recovery, publicação imutável, authorities duais,
bridge `0/1`, manager e isolamento de secrets/produção: `0 Critical / 0
Important`.
