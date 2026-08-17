#!/usr/bin/env bash
# ============================================================================
# Medição do impacto da Fase 1 (mensagem de registro determinística).
# Compara custo/turno da recomposição ANTES (22-25/05) × DEPOIS (>=26/05) do
# deploy (25/05 ~12:20 BRT) + conta quantos registros foram pelo caminho novo.
# Envia o resultado no Telegram (mesmos destinatários da auditoria).
# Agendado p/ rodar UMA vez (cron 28/05). One-off.
# ============================================================================
set -uo pipefail
export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
cd /root/agentempp || exit 1
SUPA=$(grep -E '^SUPABASE_ACCESS_TOKEN=' .env.local | head -1 | cut -d= -f2-)
BOT=$(grep -E '^TELEGRAM_BOT_TOKEN=' .env.local | head -1 | cut -d= -f2-)
PROJ="xuxehkhdvjivitduarvb"
q(){ curl -s -X POST "https://api.supabase.com/v1/projects/$PROJ/database/query" -H "Authorization: Bearer $SUPA" -H "Content-Type: application/json" -d "$(jq -nc --arg q "$1" '{query:$q}')"; }

DET=$(q "SELECT count(*) AS n FROM product_events WHERE event='pipeline.deterministic_registration' AND occurred_at >= '2026-05-25T15:20:00Z'" | jq -r '.[0].n // 0')
ANTES=$(q "SELECT ROUND(AVG(cost_usd)::numeric,4) AS c, count(*) AS n FROM messages WHERE direction='out' AND agent_stage='recomposicao' AND cost_usd IS NOT NULL AND created_at >= '2026-05-22' AND created_at < '2026-05-25T15:20:00Z'")
DEPOIS=$(q "SELECT ROUND(AVG(cost_usd)::numeric,4) AS c, count(*) AS n FROM messages WHERE direction='out' AND agent_stage='recomposicao' AND cost_usd IS NOT NULL AND created_at >= '2026-05-26'")
CA=$(echo "$ANTES" | jq -r '.[0].c // "n/d"'); NA=$(echo "$ANTES" | jq -r '.[0].n // 0')
CD=$(echo "$DEPOIS" | jq -r '.[0].c // "n/d"'); ND=$(echo "$DEPOIS" | jq -r '.[0].n // 0')
CUSTO=$(q "SELECT ROUND(SUM(cost_usd)::numeric,2) AS c FROM messages WHERE direction='out' AND cost_usd IS NOT NULL AND created_at >= '2026-05-26'" | jq -r '.[0].c // "n/d"')

MSG="*Medição Fase 1 (registro determinístico) — 28/05*

🔧 Registros pelo caminho novo (sem 2ª chamada do LLM): *${DET}*
💸 Custo/turno na recomposição:
• ANTES (22-25/05): \$${CA} (${NA} turnos)
• DEPOIS (>=26/05): \$${CD} (${ND} turnos)
💰 Custo total desde 26/05: \$${CUSTO}

Se o custo/turno caiu e há registros determinísticos, a Fase 1 está cortando custo como esperado. Se o volume seguiu baixo, os números são preliminares."

# Dado INTERNO de custo/token → SÓ pro Eduardo (não vai pro Roberto/cliente).
EDU="804776153"
R=$(curl -s -X POST "https://api.telegram.org/bot${BOT}/sendMessage" -H 'Content-Type: application/json' -d "$(jq -nc --arg c "$EDU" --arg t "$MSG" '{chat_id:$c,text:$t,parse_mode:"Markdown"}')")
[[ "$(echo "$R" | jq -r '.ok')" != "true" ]] && curl -s -X POST "https://api.telegram.org/bot${BOT}/sendMessage" -H 'Content-Type: application/json' -d "$(jq -nc --arg c "$EDU" --arg t "$MSG" '{chat_id:$c,text:$t}')" >/dev/null
echo "medição enviada p/ Eduardo: det=$DET antes=$CA depois=$CD"
