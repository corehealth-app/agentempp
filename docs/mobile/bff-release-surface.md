# Superfície do BFF na entrega de protocolos

O inventário fechado desta fatia contém **55 rotas**: as 54 anteriores e `workouts/[id]/strength-clarification/route.ts`, com `GET`, `POST` e `runtime`. A confirmação e o Histórico usam o UUID oficial do treino. As flags próprias continuam OFF por padrão; corrigir estes gates de QA não ativa nem publica o recurso.

## Identidade de fonte

- Stream path/exports dos 55: `96da71b91e2f8f7a730c98b2388128fdd840846437a4bbcf238dd8dd2fb4a62d`.
- Remover somente a pergunta recompõe exatamente 54 e o golden anterior `0f076fc83228e8742e107ba4bb9631019b6d1e6edc74fbd36039c574b228c1a3`.
- Stream das URLs compiladas: `5518c2a2938b4d95b86d7ac6c00d20b1dd2cdb4cfd716d141682708edbabd1b7`; remover somente a URL nova recompõe o golden de 54 `575bdb7757a730761d443ee35ee9749c90df5e85263e482e5bd70446bfef3d2b`.
- `auth/password-recovery` não pertence a esta entrega. O inventário antigo de 55 que incluía Auth era outra composição. Duas fixtures negativas mantêm a rejeição de Auth, tanto ao substituir a pergunta mantendo 55, quanto ao acrescentar a rota e formar 56.

## Ledger de dependências

O build local isolado recompõe os controles anteriores: original 50 sem finalização/parser novo mantém 5320 referências e 175 targets; edição de refeição mantém 107 referências; cada rota de fotos mantém 109. O total anterior das 54 é5755/181targets. A pergunta acrescenta 105 referências e seu manifesto. Seu parser puro compartilhado acrescenta uma referência em seis rotas antigas (Hoje e cinco rotas de revisão de treino), além de ser usado pela pergunta. Resultado fechado: **5866 referências, 183 targets, 181 arquivos e 2 diretórios**.

Os testes identificam o parser por semântica e conjunto exato de sete consumidores; não fixam o número gerado do chunk. O leitor/escritor da pergunta continua alcançável só na rota própria. Fábricas antigas, worker, painel, páginas, middleware e Server Actions continuam excluídos; catálogos Flow conservam seus hashes e exclusividade. Negativos de target trocado/duplicado/fora do prefixo/ausente, realpath externo, diretório arbitrário e arquivo especial permanecem ativos.

A preparação usou snapshot de código commitado e dependências offline locais, sem copiar `.env`, arquivos em andamento ou `.next` de outra composição. Arquivos de recuperação de senha em andamento são preservados fora do candidato. Os scripts do index/commit podem portanto diferir dos seus bytes de trabalho enquanto essa frente continuar adiada; não sobrescrever esse trabalho para obter um status verde.

Este ledger é evidência de build e controles locais. Integração HTTP/JWT/PostgREST, dados persistidos, candidato iOS/Release, ativação e distribuição exigem seus gates próprios. Não houve mudança no motor legado/WhatsApp.
