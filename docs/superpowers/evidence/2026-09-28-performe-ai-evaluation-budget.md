# Performe AI — proposta de teto de gasto de API para a avaliação de 30 dias

Data: 2026-09-28. **Proposta para decisão do Eduardo (gate D). Nada foi
contratado, recarregado ou configurado.**

Escopo: 3 contas (Eduardo, Roberto e a esposa de Roberto), 30 dias, ambiente
de staging. Este teto é separado do limite de **US$ 15** desta rodada técnica,
que cobre os testes de engenharia e do qual o staging registrou US$ 0,104 até
agora. Claude Code e Apple não entram em nenhum dos dois.

## 1. Preços oficiais (consultados em 28/09/2026)

| Uso no app | Modelo | Preço |
|---|---|---|
| Texto de refeição, transcrição estruturada, estrutura de plano importado | `anthropic/claude-haiku-4.5` via OpenRouter | US$ 1,00 por milhão de tokens de entrada; US$ 5,00 por milhão de saída |
| Foto de refeição e de plano | `google/gemini-2.5-flash` via OpenRouter | US$ 0,30 por milhão de entrada; US$ 2,50 por milhão de saída |
| Foto de rótulo | `anthropic/claude-sonnet-4.6` via OpenRouter | US$ 3,00 por milhão de entrada; US$ 15,00 por milhão de saída |
| Áudio | `whisper-large-v3-turbo` no Groq | US$ 0,04 por hora de áudio |
| Flow | modelo definido em `v_active_prompts` no staging; o roteador pode usar `anthropic/claude-4.5-haiku` | Não confirmado; ver seção 3 |

Fontes: API pública de modelos do OpenRouter (`https://openrouter.ai/api/v1/models`)
e página do modelo no Groq (`https://console.groq.com/docs/model/whisper-large-v3-turbo`).

## 2. Custo estimado por operação

**Os tamanhos de requisição são hipóteses**, não medições. Eles devem ser
trocados pelos custos reais registrados nos primeiros dias
(`messages.cost_usd` e o painel do OpenRouter).

| Operação | Hipótese de tokens | Custo estimado |
|---|---|---|
| Refeição por texto | 2.000 entrada, 400 saída (Haiku) | US$ 0,004 |
| Refeição por foto | 3.000 entrada, 800 saída (Gemini Flash) | US$ 0,003 |
| Foto de rótulo | 3.000 entrada, 600 saída (Sonnet) | US$ 0,018 |
| Refeição por áudio (1 min) | Whisper + texto de refeição | US$ 0,005 |
| Mensagem ao Flow (Haiku) | 12.000 entrada por chamada, 1,5 chamada por mensagem, 400 saída | US$ 0,02 |
| Mensagem ao Flow (se o modelo for Sonnet) | mesmo volume | US$ 0,06 |
| Importação de plano | transcrição da foto + estrutura (Haiku) | US$ 0,02 |
| Proposta de plano pelo Flow | 12.000 entrada, 3.000 saída (Haiku) | US$ 0,03 |

## 3. Cenários para os 30 dias (3 participantes)

| Cenário por participante e por dia | Refeições | Flow | Custo/dia por pessoa | Total 30 dias × 3 |
|---|---|---|---|---|
| Leve | 3 por texto, 1 foto a cada 2 dias | 3 mensagens | ≈ US$ 0,08 | **≈ US$ 7** |
| Típico | 2 texto, 2 foto, 1 áudio, 1 rótulo a cada 3 dias; 2 planos no mês | 8 mensagens | ≈ US$ 0,20 | **≈ US$ 18** |
| Intenso | 2 texto, 4 foto, 2 áudio, 1 rótulo | 25 mensagens | ≈ US$ 0,55 | **≈ US$ 49** |
| Típico com Flow em Sonnet | como o típico | 8 mensagens | ≈ US$ 0,51 | **≈ US$ 46** |

O Flow responde por 80% a 95% do custo, conforme o cenário. O modelo
configurado para o Flow no staging é o fator que mais muda o total.

## 4. Proposta

1. **Teto de US$ 30 para os 30 dias**, somando todos os provedores. Ele cobre
   o cenário típico com margem de cerca de 60%.
2. **Limite de crédito na chave do OpenRouter usada pelo staging**, no valor
   do teto, configurado pelo Eduardo no painel. O código atual não tem teto
   diário nem por usuário: só 10 mensagens por minuto no Flow e um alerta de
   saldo em US$ 20.
3. **Groq:** o custo previsto é inferior a US$ 1. Se o console não oferecer
   um limite rígido, manter a regra desta operação de não usar recarga
   automática.
4. **Sem recarga automática, sem renovação e sem provedor pago de reserva.**
5. **Revisão no 3º dia** com os custos reais. Se a projeção passar do teto,
   as opções são reduzir o modelo do Flow ou pausar a avaliação. Nenhuma das
   duas acontece sem decisão do Eduardo.

## 5. O que precisa do Eduardo
- Aprovar ou mudar o teto de US$ 30.
- Confirmar qual modelo o Flow usa no staging.
- Configurar o limite de crédito da chave do OpenRouter do staging. Esse
  passo depende da contenção das credenciais expostas (gate A), porque a
  chave precisa ser uma que não esteja exposta.
