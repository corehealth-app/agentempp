# Região da função do BFF mobile: São Paulo (gru1)

`apps/mobile-bff/vercel.json` fixa a região das funções do BFF (o servidor do
app, onde roda o chat do Flow) em **gru1 (São Paulo)**. O arquivo não configura
mais nada. O conteúdo é travado por `apps/mobile-bff/src/function-region.test.ts`.

> **Premissa.** A Vercel só obedece o `vercel.json` que está no Root Directory
> do projeto. O Root Directory do projeto `agentempp-mobile-bff-staging` não
> está escrito no repositório; pelo log do deploy (build em
> `/vercel/path0/apps/mobile-bff`, Next detectado, e o `package.json` da raiz
> não tem `next`) ele é `apps/mobile-bff`. Se no painel for outro, o arquivo é
> ignorado em silêncio. A conferência abaixo (cabeçalho `x-vercel-id`) decide.

## O que foi medido (2026-10-04, staging)

- A função roda em **iad1 (Virgínia)**: o cabeçalho de resposta é
  `x-vercel-id: gru1::iad1::…` (entra por São Paulo, executa na Virgínia).
- Os dois bancos Supabase (staging e produção) estão em **sa-east-1 (São Paulo)**.
- Um turno do Flow faz **32 a 35 idas ao banco, uma depois da outra**: 18 fora
  do agente (login, assinatura, idempotência, gravação das mensagens) e 14 a 17
  dentro dele.
- Uma resposta pronta, **sem chamar modelo, levou 4,3 s**. São 14 idas ao banco:
  4,3 ÷ 14 ≈ 0,31 s por ida.

## Por que gru1

Hoje cada ida ao banco atravessa São Paulo ↔ Virgínia (cerca de 0,11 a 0,13 s
de ida e volta). Com a função ao lado do banco, esse trecho some em todas elas.
Não muda prompt, cálculo, texto ao paciente nem custo de modelo (tokens: 0,
US$: 0). Só muda a espera.

## Economia esperada por turno (estimativa, confirmar no preview)

| Conta | Resultado |
| --- | --- |
| Só a distância: 32 idas × 0,11 s | −3,5 s |
| Teto: 14 × (0,31 − 0,06) + 18 × 0,08 + 0,11 (salto app → função) | −5,0 s |
| Piso (se só metade do trecho for distância): 32 × 0,06 s | −1,9 s |
| Cada chamada de modelo (provedor nos EUA) | +0,12 s |

- Resposta sem modelo: **−3,5 a −5 s** (piso −2 s).
- Uma chamada de modelo: −3,4 a −4,9 s. Duas chamadas: −3,3 a −4,8 s.
- Turno simples: de 5,9–7,5 s no servidor para cerca de 2,5–3,5 s.

Não sabemos quanto dos 0,31 s por ida é distância e quanto é o banco de
staging. Só a medição no preview responde.

Os números acima valem para o build medido (`ff50a9e`, 32 a 35 idas em série).
O serviço do chat passou a fazer as leituras independentes em paralelo no mesmo
lote (26 a 29 idas em série por turno), então, publicadas juntas, a parte da
região cai na mesma proporção: só a distância 26 × 0,11 ≈ −2,9 s (piso
26 × 0,06 ≈ −1,6 s). As duas economias não se somam: atacam as mesmas idas.

## O que fica ~0,12 s mais lento

Chamadas a provedores nos EUA ganham uma ida e volta: o modelo (OpenRouter), a
transcrição de áudio (Groq), a visão e o envio de evento ao Inngest nas rotas
de mídia. Em todas, o ganho nas idas ao banco é maior que essa perda.

## Como conferir depois do deploy de preview

1. `curl -sI <preview>/api/mobile/v1/me` → `x-vercel-id` com `gru1` no segundo
   trecho (hoje `iad1`).
2. Repetir a pergunta de resposta pronta e ler `messages.latency_ms`: hoje
   4,3 s; esperado abaixo de ~1,5 s.
3. Repetir quatro turnos simples: hoje 5,9–7,5 s.

O preview novo tem endereço novo: o iPhone precisa de novo xcconfig.

## Limites

- **Produção:** qualquer deploy de produção exige autorização explícita do
  Eduardo. Este arquivo só vale quando um deploy for publicado.
- **Projeto admin (`agentempp`): região NÃO muda.** Ele serve o pipeline do
  WhatsApp e o Inngest; a região dele é decisão separada do dono.
- Em plano pago da Vercel, o preço por unidade em gru1 é maior que em iad1
  (valor não conferido).
- Não usar `preferredRegion` por rota: quebra os espelhos congelados das 48
  rotas (`verify:routes`).

## Como reverter

Apagar `apps/mobile-bff/vercel.json` (e o teste
`apps/mobile-bff/src/function-region.test.ts`, que exige o arquivo) e publicar
novo preview. O preview anterior continua no ar e o iPhone pode voltar a
apontar para ele.
