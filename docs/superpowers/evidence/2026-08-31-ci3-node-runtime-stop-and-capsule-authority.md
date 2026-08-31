# CI-3 — STOP do runtime e authority do capsule Node imutável

**Data:** 2026-08-31
**Dossiê:** 1.7.3
**Arquitetura:** `PRIVATE_VERSIONED_IMMUTABLE_NODE_RUNTIME_CAPSULE_V1`
**Status inicial:** `AUTHORITY_AUTHORED_RUNTIME_NOT_YET_CREATED`
**Status terminal:** `STOP_DOCUMENTED_DYNAMIC_CLOSURE_PRE_CLAIM`

## 1. Ruling preservado

O STOP anterior permanece correto. A ponte publicada em
`ba8473799a19aec586b0fe706bb7d4084589c86c` exigia Node root-owned e
imutável. `/usr/bin/node` era root-owned, `0755`, single-link e tinha SHA-256
`6295488653f0d93b0a157841746fef7e72cc4328cfb60c4bbe0ca2668a836ffd`,
mas não possuía immutable flag. O Node NVM pertencia a `1000:1000` e também
não era imutável. Nenhum teste do generator, claim ou bundle havia sido
criado; o budget da ponte continuava `0/1`.

Esta authority não modifica o bootstrap. Ela autoriza exclusivamente uma
cópia privada, root-owned, version-addressed, `0555`, single-link e com
immutable flag real. `/usr/bin/node` permanece bootstrap-only. NVM, PATH,
package manager e bibliotecas do sistema não são alterados.

## 2. Autoridades duais

- Componentes da ponte e generator:
  `ba8473799a19aec586b0fe706bb7d4084589c86c`.
- Capsule do runtime: o commit único com subject
  `build(ops): authorize immutable VPS Node runtime capsule` e parent exato
  `ba8473799a19aec586b0fe706bb7d4084589c86c`.

O runtime authority não substitui nem regrava a bridge authority. O bridge
generator futuro roda em worktree detached limpa no SHA `ba847...`, mas seu
processo Node é exclusivamente o capsule publicado pela segunda authority.

## 3. Bootstrap e closure read-only

O bootstrap literal é `/usr/bin/node`. Foram congelados realpath,
owner/group/mode/link, tamanho, device, inode, mtime/ctime nanosegundos,
SHA-256, versão, hash estrutural de `process.versions`, ELF build ID, package
ownership, parent chain, filesystem e atributos. A closure dinâmica tinha seis
entradas e foi registrada somente por count/hash. Nenhum valor sensível foi
publicado.

As ferramentas absolutas `chattr`, `lsattr`, `stat`, `sha256sum`, `findmnt`,
`ldd`, `readelf` e `git` foram ligadas por path/hash/identidade. O source pode
continuar sem immutable flag, pois não é o runtime operacional da ponte.

## 4. Contrato do builder

`scripts/ci3/create-immutable-node-runtime-capsule.mjs` usa apenas módulos core
e aceita somente `--self-test`, `--create` e `--verify`. `--create` e
`--verify` exigem snapshot root-owned `0600`, materializado do blob Git
publicado sob `.builders/<authority>/`; worktree source não é entrypoint real.

O claim `O_EXCL|O_NOFOLLOW`, attempt `1`, retry false e fsync precede o probe
e toda cópia. O probe usa um arquivo sintético próprio: aplica `+i`, comprova
write/unlink/rename negados, remove `i` apenas desse probe e o apaga. O builder
nunca executa `chattr` contra `/usr/bin/node` ou NVM.

O source é aberto no-follow uma vez e reobservado por descriptor/path. Os
mesmos bytes são gravados em staging, fsyncados, relidos e executados para
version/core/syntax smokes. Node e receipt são promovidos sem clobber e
terminam single-link; depois recebem `+i`. O diretório final vira `0555` e
recebe `+i`. Não existe `current`, `latest`, symlink ou alias mutável.

Claim existente nunca reinicia o efeito. Somente capsule exato com claim
original é verificável; prefixo parcial, unclaimed ou divergente é STOP e fica
preservado. O capsule publicado jamais recebe `chattr -i`.

## 5. Receipt e política

O receipt sanitizado liga runtime commit/parent/tree/subject, manifest de sete
paths, builder blob/hash, source path/hash/version/identidade, capsule path
hash/hash/identidade, owner/mode/link, flags dos três objetos, hashes de
`chattr`/`lsattr`, filesystem, closure before/after e probe. Também fixa:

```text
source_immutable=false
source_role=bootstrap_only
secrets_read=false
network_calls=0
package_manager_write=false
system_node_modified=false
nvm_modified=false
raw_values_reported=false
```

## 6. Allowlist e TDD

O commit contém exatamente sete paths: este evidence, dossiê, spec, dois
plans, builder e teste. Generator, controller, launcher, writer,
package/lockfiles, iOS, backend e migrations não mudam.

O primeiro gate foi RED `111 total / 83 pass / 28 fail`, todos na contagem do
schema do receipt. Após corrigir a projeção exata de 45 campos, o reader de
libraries e ampliar as coberturas comportamentais do probe, exact-existing e
receipt, o gate ficou `127/127`, zero fail/skip/todo; syntax PASS e self-test
`8/8`, com network/secrets/system-node/NVM iguais a zero. Os testes são
sintéticos: não aplicam `chattr` real nem abrem os cinco inputs da ponte.

## 7. Continuidade e limites

Depois do capsule PASS, o generator da bridge será materializado somente do
blob `905d21bdc063602d2d0c98d749ad85795aad3d2f` e executado em worktree
detached `ba847...`, exclusivamente com o capsule. O budget da ponte continua
`0/1` até essa execução. Credential é referenciada por path/hash e nunca
copiada; service role, token, PII, origin e valores de configuração não são
emitidos.

Esta authority não executa Supabase, Vercel, banco, primary/live, produção,
Mac, simulador, CI-3 Task 2, CI-4 ou cleanup.

## 8. Reviews

Review A cobriu runtime/filesystem, sequência claim-before-effect, no-follow,
fsync, no-clobber, exact-existing, imutabilidade e invariância do bootstrap.
Resultado: `GO — 0 Critical / 0 Important / 0 Minor`.

Review B cobriu continuidade da ponte, authorities duais, allowlist, isolamento
de secrets, ausência de diff em bridge/package/lock e compatibilidade do handoff
Mac. Resultado: `GO — 0 Critical / 0 Important / 0 Minor`.

## 9. Publicação e STOP físico

A authority foi publicada por push não-force em
`f039fe38b35084a33a4b7a3649b1112f26a93fb2`, parent `ba847...`, tree
`608a75fd973eb19a095127d2fc9d253a271f21d0`. O builder publicado tem blob
`c2d7173d8b54984a928a447dbfe7ece60975474e` e SHA-256
`8447f0e59568049c3bbd73a145a6dcde5c5ce84da1253ac0f54e19d097452727`.
Seu snapshot físico passou owner/mode/link/hash/readback e self-test.

A única invocação `--create` retornou `ERROR DYNAMIC_CLOSURE`. A leitura
forense posterior confirmou sete entradas no output corrente do `ldd`, das
quais duas são symlink entries. O builder chama o reader de arquivo regular
no-follow diretamente nessas entradas, rejeitando-as antes de resolver seu
target canônico. O problema não foi coberto pelos testes sintéticos nem pelas
duas revisões prévias.

O STOP ocorreu antes da publicação do claim. Não existem claim, probe,
staging, diretório final, Node capsule ou receipt. A invocação lógica foi
consumida `1/1`, portanto não houve retry nem cleanup. O bridge generator não
foi materializado ou executado; budget da bridge `0/1`.

O bootstrap preserva SHA-256
`6295488653f0d93b0a157841746fef7e72cc4328cfb60c4bbe0ca2668a836ffd`,
root:root, `0755`, single-link e sem immutable flag, exatamente como antes.
Manager e os 25 itens históricos também permanecem byte-preservados. A
retomada exige nova authority para canonicalizar cada library sem seguir um
pathname mutável durante a leitura e para conceder novo budget explícito.
