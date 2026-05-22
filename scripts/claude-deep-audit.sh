#!/usr/bin/env bash
# ============================================================================
# Auditoria profunda (Claude como ANALISTA, sem ferramentas) + Telegram.
# ============================================================================
# Roda via cron 5x/dia (11/15/18/21/00 UTC = 8/12/15/18/21 BRT).
#
# DESENHO SEGURO: o SCRIPT faz toda a leitura do banco (somente SELECT) e a
# entrega; o Claude SÓ analisa o dossiê e escreve o relatório (--allowedTools ""
# => sem Bash, sem acesso a banco, sem escrita, sem bypass de permissão). Logo
# o Claude NÃO consegue alterar dado de paciente — ele só raciocina e reporta.
# Correções viram texto pronto pro humano aplicar (1 confirmação).
# ============================================================================
set -uo pipefail
# cron tem PATH mínimo — garante claude/jq/curl/node
export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
cd /root/agentempp || exit 1

PROMPT_FILE="/root/agentempp/scripts/claude-deep-audit-prompt.md"
LOG_DIR="/root/agentempp/.audit-logs"; mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/audit-$(date -u +%Y%m%dT%H%M%S).log"
MODEL="${AUDIT_MODEL:-claude-sonnet-4-6}"
TEST_CHAT="${AUDIT_TEST_CHAT:-}"   # se setado, envia SÓ pra esse chat (teste)

SUPA_TOKEN=$(grep -E '^SUPABASE_ACCESS_TOKEN=' .env.local | head -1 | cut -d= -f2-)
BOT=$(grep -E '^TELEGRAM_BOT_TOKEN=' .env.local | head -1 | cut -d= -f2-)
PROJ="xuxehkhdvjivitduarvb"

q() { # roda SQL e devolve JSON
  curl -s -X POST "https://api.supabase.com/v1/projects/$PROJ/database/query" \
    -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
    -d "$(jq -nc --arg q "$1" '{query:$q}')"
}

echo "[$(date -u +%H:%M:%S)] coletando dossiê (36h)" | tee -a "$LOG_FILE"

# A) heurística: maior "Consumido" nos cards vs snapshot por dia (gap>60 = suspeito)
A=$(q "WITH cards AS (SELECT m.user_id, (m.created_at AT TIME ZONE 'America/Sao_Paulo')::date AS dia, MAX(NULLIF(regexp_replace(substring(m.content from 'Consumido:[^0-9]*([0-9][0-9.]*)'),'\.','','g'),'')::int) AS card FROM messages m WHERE m.direction='out' AND m.created_at > now() - interval '36 hours' AND m.content ~* 'Consumido:' GROUP BY 1,2) SELECT u.name, c.dia, c.card, ds.calories_consumed AS snap, (c.card-ds.calories_consumed) AS gap FROM cards c JOIN users u ON u.id=c.user_id LEFT JOIN daily_snapshots ds ON ds.user_id=c.user_id AND ds.date=c.dia WHERE ds.calories_consumed IS NOT NULL AND (c.card-ds.calories_consumed)>60 ORDER BY gap DESC;")

# B) cards outbound que afirmam registro (contexto pra cruzar)
B=$(q "SELECT u.name, to_char(m.created_at AT TIME ZONE 'America/Sao_Paulo','MM-DD HH24:MI') AS brt, left(m.content,180) AS card FROM messages m JOIN users u ON u.id=m.user_id WHERE m.direction='out' AND m.created_at > now() - interval '36 hours' AND m.content ~* '(registrad|salv|anotad|Total refei|corrigid)' ORDER BY u.name, m.created_at;")

# C) inbound 36h (pra detectar silêncio: pedido sem resposta/log)
C=$(q "SELECT u.name, to_char(m.created_at AT TIME ZONE 'America/Sao_Paulo','MM-DD HH24:MI') AS brt, m.content_type AS tipo, left(coalesce(m.content,''),120) AS msg FROM messages m JOIN users u ON u.id=m.user_id WHERE m.direction='in' AND m.created_at > now() - interval '36 hours' ORDER BY u.name, m.created_at;")

# D) meal_logs 36h (pra cruzar com os cards)
D=$(q "SELECT u.name, (ml.consumed_at AT TIME ZONE 'America/Sao_Paulo')::date AS dia, ml.meal_type AS ref, ml.food_name AS item, ml.kcal, ml.source FROM meal_logs ml JOIN users u ON u.id=ml.user_id WHERE ml.created_at > now() - interval '36 hours' ORDER BY u.name, dia, ml.consumed_at;")

# E) snapshots 4 dias (integridade)
E=$(q "SELECT u.name, ds.date AS dia, ds.calories_consumed AS consumido, ds.calories_target AS meta, ds.daily_balance AS saldo, ds.day_closed FROM daily_snapshots ds JOIN users u ON u.id=ds.user_id WHERE ds.date >= (now() AT TIME ZONE 'America/Sao_Paulo')::date - 3 ORDER BY u.name, ds.date;")

NOW_BRT=$(TZ=America/Sao_Paulo date '+%Y-%m-%d %H:%M BRT')
DOSSIE=$(printf '%s\n\nGerado: %s\n\n## A) Heurística card-Consumido vs snapshot (gap>60 = suspeito)\n%s\n\n## B) Cards outbound que afirmam registro\n%s\n\n## C) Mensagens recebidas (36h) — pra detectar silêncio\n%s\n\n## D) meal_logs gravados (36h)\n%s\n\n## E) Snapshots (4 dias)\n%s\n' \
  "$(cat "$PROMPT_FILE")" "$NOW_BRT" "$A" "$B" "$C" "$D" "$E")

echo "[$(date -u +%H:%M:%S)] analisando com $MODEL (sem ferramentas)" | tee -a "$LOG_FILE"
REPORT=$(printf '%s' "$DOSSIE" | timeout 300 claude -p --allowedTools "" --model "$MODEL" 2>>"$LOG_FILE")
RC=$?
echo "[$(date -u +%H:%M:%S)] claude rc=$RC, ${#REPORT} chars" | tee -a "$LOG_FILE"

[[ -z "$REPORT" ]] && REPORT="⚠️ Auditoria profunda rodou mas não gerou relatório (rc=$RC). Log: $LOG_FILE"
printf '%s\n' "$REPORT" > "$LOG_DIR/report-$(date -u +%Y%m%dT%H%M%S).md"  # rastreabilidade

# destinatários
if [[ -n "$TEST_CHAT" ]]; then
  RECIPIENTS="$TEST_CHAT"
else
  RECIPIENTS=$(q "SELECT value FROM global_config WHERE key='audit.telegram_chat_ids'" | jq -r '.[0].value[]?' 2>/dev/null)
  [[ -z "$RECIPIENTS" ]] && RECIPIENTS="804776153"
fi

send_one() {
  local chat="$1" txt="$2" resp
  resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT}/sendMessage" -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg c "$chat" --arg t "$txt" '{chat_id:$c,text:$t,parse_mode:"Markdown",disable_web_page_preview:true}')")
  [[ "$(echo "$resp" | jq -r '.ok')" != "true" ]] && resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT}/sendMessage" -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg c "$chat" --arg t "$txt" '{chat_id:$c,text:$t,disable_web_page_preview:true}')")
  echo "  -> chat $chat ok=$(echo "$resp" | jq -r '.ok')" | tee -a "$LOG_FILE"
}
for chat in $RECIPIENTS; do send_one "$chat" "$REPORT"; done

echo "[$(date -u +%H:%M:%S)] fim" | tee -a "$LOG_FILE"
ls -1t "$LOG_DIR"/audit-*.log 2>/dev/null | tail -n +31 | xargs -r rm -f
