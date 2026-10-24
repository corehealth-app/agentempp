# Superfície do BFF na entrega de protocolos

O inventário contém **56 rotas**: as 55 da entrega de protocolos e `onboarding/completion-intent/route.ts`. A confirmação e o Histórico usam o UUID oficial do treino. Os leitores C13 recuperam o comentário salvo na confirmação original. Qualificação de fonte e build é separada de ativação, QA autenticado e distribuição.

## Identidade de fonte

- Stream path/exports dos 56: `b88a27d2d694fb0ca539b9075c369978956d51aa25427b52da46983919b7d0e8`.
- Remover somente completion-intent recompõe os 55 e `96da71b91e2f8f7a730c98b2388128fdd840846437a4bbcf238dd8dd2fb4a62d`; remover também a pergunta recompõe os 54 e `0f076fc83228e8742e107ba4bb9631019b6d1e6edc74fbd36039c574b228c1a3`.
- Stream das URLs compiladas: `75c8979e64a793a209a621914eec758d1b061820b30c68488622900c2b3bf71a`. Os controles históricos de 55/54 continuam nos testes.
- `auth/password-recovery` continua fora desta entrega. Seus arquivos em andamento são preservados fora do candidato; os negativos mantêm a rejeição de composições que a incluam.

## Ledger de dependências

Os controles históricos permanecem: original 50 sem finalização/parser/draft novo, 5320 referências e 175 targets; edição de refeição, 107; cada rota de fotos, 109. As 54 somam 5755/181. A pergunta acrescenta 105 e seu manifesto; o parser puro acrescenta seis referências antigas: 5866/183. Completion-intent acrescenta 104 e seu manifesto: 5970/184. O chunk compartilhado de draft acrescenta uma referência em seis rotas: **5976 referências / 185 targets** antes de C13.

C13 acrescenta **57 referências**, totalizando **6033 referências / 187 targets / 185 arquivos / 2 diretórios**:

| Contribuição | Referências novas |
|---|---:|
| Nove JSONs aprovados em cinco rotas de revisão | 45 |
| Catálogo/seletor compartilhado em Flow e cinco revisões | 6 |
| Folha de recibo nas duas rotas do Histórico | 2 |
| Read model existente nas duas rotas do Histórico | 2 |
| Estado oficial e seletor legado existentes no detalhe do treino | 2 |

O chunk de revisão/escrita substitui seu predecessor com saldo zero. Os testes identificam cada contribuição por marcadores semânticos, caminho físico dentro de chunks, consumidores e ocorrência exatos. Removem somente essas contribuições para recompor os números anteriores e o hash das contagens por rota `a89cfdaa746fd822c59908f78e15920a97edcf500b09e60490693b32a287ac7c`. Isso prova contagens e fronteiras semânticas; não significa igualdade de todo JavaScript compilado.

### Fronteiras C13

- Catálogos: mesmos nove hashes, somente Flow e `me`, `pending`, `registrations/propose`, `registrations/[id]`, `registrations/[id]/confirm`.
- Chunk de revisão/escrita e writer de feedback: somente as cinco revisões, conferindo tanto entrypoints quanto JS transitivo. A flag de treino também permanece no entrypoint da pergunta de esclarecimento, como antes de C13; o conjunto total da flag continua em seis rotas.
- Repositório protegido: duas variantes compiladas, união exata das cinco revisões e dos dois detalhes do Histórico; uma variante por rota. Isso é alcance de código, não prova de execução/autorização.
- `meal-records/[id]` e `workouts/[id]/strength-clarification`: leem o recibo salvo, sem catálogo JSON, cursor compartilhado ou writer C13. Reabertura não gera comentário nem consulta o estado diário pelo leitor de recibo.
- Parser de fatos, finalização, fotos e demais controles históricos conservam os conjuntos exatos de consumidores. Fábricas antigas, worker, painel, páginas, middleware e Server Actions continuam excluídos. Negativos de target trocado/duplicado/fora do prefixo/ausente, realpath externo, diretório arbitrário e arquivo especial permanecem ativos.

A preparação usou snapshot de código commitado e dependências offline locais, sem copiar `.env`, arquivos em andamento ou `.next` de outra composição. Arquivos de recuperação de senha em andamento são preservados fora do candidato. Os scripts do index/commit podem portanto diferir dos seus bytes de trabalho enquanto essa frente continuar adiada; não sobrescrever esse trabalho para obter um status verde.

Este ledger é evidência de build e controles locais. Integração HTTP/JWT/PostgREST, dados persistidos, candidato iOS/Release, ativação e distribuição exigem seus gates próprios. A separação do leitor de recibo não muda fórmulas, schemas ou writers do motor compartilhado com o legado WhatsApp.
