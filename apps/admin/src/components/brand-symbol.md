# Marca Performe AI no painel

Os dois arquivos de `apps/admin/public/brand/` são cópias idênticas (byte a byte) dos
masters aprovados do símbolo "Signal Spark". Este texto fica ao lado do componente
(`brand-symbol.tsx`), fora de `public/`, para não ser servido pelo painel.

| Arquivo em `public/brand/` | Origem | SHA-256 |
| --- | --- | --- |
| `symbol-light.svg` | `assets/brand/performe-ai-public-v1/masters/symbol-light.svg` | `53e359787682213487fdf8c9f116bf62b317f9d776f171e66524642fd61e9bd0` |
| `symbol-negative.svg` | `assets/brand/performe-ai-public-v1/masters/symbol-negative.svg` | `7ca4202173006a7dccbe6c3c3f74ef36f7edbc4b738b2d2cca6375fcb9da1ffc` |

Os hashes são os de `assets/brand/performe-ai-public-v1/manifest.json` (`approvedFiles`).

**Cópias idênticas: não editar, não recolorir, não reexportar.** Para atualizar, copie de
novo o master com `cp` e confira o SHA-256 contra o manifest.

Onde são usados:

- `symbol-negative.svg` — coluna escura do login.
- `symbol-light.svg` — menu lateral, cabeçalho no celular, login no celular e favicon
  (`icons` em `src/app/layout.tsx`).

Uso no painel feito pela instrução do dono de 2026-10-05 de alinhar o painel ao app
Performe AI. O `manifest.json` da marca não foi alterado: a lista `publicCallsites` de lá
continua nomeando só os locais do app iOS.
