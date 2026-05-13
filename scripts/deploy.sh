#!/usr/bin/env bash
# ============================================================================
# Deploy seguro: vercel --prod + sync Inngest + smoke test.
# ============================================================================
# Context (2026-05-13): deploy manual via `vercel --prod` NÃO aciona auto-sync
# do Inngest. Resultado: funções ficam registradas com versão antiga, webhook
# recebe msgs mas pipeline não responde. Sistema fica mudo até alguém perceber.
#
# Este script força o sync após deploy e verifica que Inngest aceitou.
# ============================================================================
set -euo pipefail

PROD_URL="${PROD_URL:-https://agentempp.vercel.app}"

echo "🚀 Deploy production..."
vercel --prod

echo ""
echo "⏳ Aguardando 5s pra alias propagar..."
sleep 5

echo ""
echo "🔄 Sincronizando Inngest (PUT $PROD_URL/api/inngest)..."
SYNC_RESP=$(curl -s -X PUT "$PROD_URL/api/inngest" -w "\n__STATUS__%{http_code}")
SYNC_BODY=$(echo "$SYNC_RESP" | sed '/__STATUS__/d')
SYNC_STATUS=$(echo "$SYNC_RESP" | grep -oP '__STATUS__\K\d+')

echo "  status=$SYNC_STATUS"
echo "  body=$SYNC_BODY"

if [[ "$SYNC_STATUS" != "200" ]]; then
  echo "❌ Inngest sync FAILED (status $SYNC_STATUS)"
  echo "   ⚠️ Pipeline pode estar dessincronizado. Investigue antes de seguir."
  exit 1
fi

# Verifica se modified=true (significa que estava out-of-sync) ou false (já sync).
if echo "$SYNC_BODY" | grep -q '"modified":true'; then
  echo "  ℹ️  Inngest estava out-of-sync — agora atualizado."
elif echo "$SYNC_BODY" | grep -q '"modified":false'; then
  echo "  ✅ Inngest já estava em sync."
fi

echo ""
echo "✅ Deploy concluído com sucesso."
echo ""
echo "Próximos passos opcionais:"
echo "  - Verificar /admin/audit pra ver saúde do pipeline"
echo "  - Verificar /admin/cron pra status dos crons"
