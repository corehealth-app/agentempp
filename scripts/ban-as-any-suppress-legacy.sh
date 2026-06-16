#!/usr/bin/env bash
# ACT-1 (prevenção 2026-06-16): suprime os casts legacy de `as any` em
# packages/agent/src/** com biome-ignore comments. Política nova: noExplicitAny
# vira `error` em packages/agent (override do biome.json) — qualquer cast novo
# quebra CI. Os casts existentes são marcados como legacy explicitamente.
#
# Usa Biome `--reporter=json` como fonte de verdade (cobre `as any`, `: any`,
# `<any>`, etc — qualquer variante de noExplicitAny). Idempotente: re-execução
# detecta linhas que já têm o marker.
set -euo pipefail
cd "$(dirname "$0")/.."

MARKER="// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16"

# Coleta diagnósticos em JSON. --max-diagnostics garante captura total.
json=$(pnpm exec biome check packages/agent/src \
  --reporter=json --max-diagnostics=999 2>/dev/null || true)

# Extrai pares "file\tline" só para noExplicitAny. Ordena por arquivo asc,
# linha DESC (insere de baixo pra cima, preservando números de linha).
echo "$json" | node -e '
  let buf = ""; process.stdin.on("data", c => buf += c);
  process.stdin.on("end", () => {
    let j; try { j = JSON.parse(buf); } catch { console.error("no biome output"); process.exit(0); }
    const rows = [];
    for (const d of (j.diagnostics ?? [])) {
      if (d.category !== "lint/suspicious/noExplicitAny") continue;
      const f = d.location?.path?.file ?? d.location?.path;
      const l = d.location?.start?.line ?? d.location?.span?.[0]?.line;
      if (typeof f === "string" && typeof l === "number") rows.push([f, l]);
    }
    rows.sort((a,b) => a[0].localeCompare(b[0]) || b[1] - a[1]);
    for (const [f,l] of rows) console.log(`${f}\t${l}`);
  });
' | while IFS=$'\t' read -r file line; do
  [[ -z "$file" || -z "$line" ]] && continue
  # Idempotência: linha anterior já tem o marker?
  prev=$((line - 1))
  if [[ $prev -ge 1 ]] && sed -n "${prev}p" "$file" | grep -q "biome-ignore lint/suspicious/noExplicitAny"; then
    continue
  fi
  # Preserva indentação da linha alvo
  indent=$(sed -n "${line}p" "$file" | sed -E 's/^([[:space:]]*).*/\1/')
  sed -i "${line}i ${indent}${MARKER}" "$file"
done

echo "Done. Re-run \`pnpm --filter @mpp/agent lint\` to confirm 0 noExplicitAny errors."
