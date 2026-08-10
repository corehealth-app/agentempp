# BodyFlow — evidência do gate de marca

Validação Linux executada em 2026-08-10 (UTC) sobre o HEAD
`a384ef66543790d219c606bb963cd4cb6312d0ac`, na branch
`codex/bodyflow-ios-brand-design-system-v1`.

Este diretório registra a aprovação visual humana recebida em 2026-08-10. O
manifesto foi promovido para `brand_version: 1.0.0` e
`approval_state: approved`. O Mac validou o snapshot candidato pré-freeze
`a384ef66543790d219c606bb963cd4cb6312d0ac`, cujo manifesto ainda era
`1.0.0-candidate.1 / candidate`; não validou um SHA que já contivesse o
manifesto aprovado. A promoção posterior de dois campos foi coberta pelos
gates Linux e pela prova de invariância descritos abaixo.

## Fonte visual aprovada

- Única autoridade visual:
  `design/brand/source/bodyflow-approved-board.jpg`.
- Dimensões: 1491 × 1055 pixels.
- Espaço de cor observado/declarado: sRGB.
- SHA-256:
  `af44d4b2036638720eaaf58c05fa6098f69b21c7639b91bb4a60bc85c64c15b7`.
- O JPEG é proveniência imutável. Não há vetor original disponível e esta
  reconstrução não reivindica identidade matemática com um vetor original.

## Evidências para o checkpoint

As três evidências são cópias mecânicas, sem reencode, dos review exports
canônicos. `cmp` confirmou igualdade byte a byte entre cada origem e destino.

| Evidência | Review export de origem | Dimensões / formato | SHA-256 |
| --- | --- | --- | --- |
| `brand-comparison.png` | `design/brand/exports/brand-comparison.png` | 1600 × 1000, PNG RGB opaco, sRGB | `822011b4478e1af322ab83c0be24d8d1a4fbbe27a57a03279cf7300822be64f4` |
| `brand-reduced-sizes.png` | `design/brand/exports/brand-reduced-sizes.png` | 1600 × 1000, PNG RGB opaco, sRGB | `263b48460df5b12fd800ccaad55768d2a17c691b397f371ba67c80e0cf67f1e1` |
| `brand-light-dark.png` | `design/brand/exports/brand-light-dark.png` | 1600 × 1000, PNG RGB opaco, sRGB | `cfca072081070b3cb94ceea8a6105c57d80bb64dceb45143e3dc740750c2d5c8` |

Comandos de cópia e prova:

```sh
cp design/brand/exports/brand-comparison.png docs/superpowers/evidence/2026-08-10-bodyflow-brand-assets/brand-comparison.png
cp design/brand/exports/brand-reduced-sizes.png docs/superpowers/evidence/2026-08-10-bodyflow-brand-assets/brand-reduced-sizes.png
cp design/brand/exports/brand-light-dark.png docs/superpowers/evidence/2026-08-10-bodyflow-brand-assets/brand-light-dark.png
cmp design/brand/exports/brand-comparison.png docs/superpowers/evidence/2026-08-10-bodyflow-brand-assets/brand-comparison.png
cmp design/brand/exports/brand-reduced-sizes.png docs/superpowers/evidence/2026-08-10-bodyflow-brand-assets/brand-reduced-sizes.png
cmp design/brand/exports/brand-light-dark.png docs/superpowers/evidence/2026-08-10-bodyflow-brand-assets/brand-light-dark.png
sha256sum docs/superpowers/evidence/2026-08-10-bodyflow-brand-assets/*.png
```

Resultado: três `cmp` com exit 0; os três SHA-256 são os valores da tabela.

## Checksums dos masters

| ID | Caminho | SHA-256 |
| --- | --- | --- |
| `symbol` | `design/brand/masters/bodyflow-symbol.svg` | `01343fcb7aa4a52b303bb9a602180f13973c74d2b53704eaa817ce1b9a9f5eb9` |
| `wordmark` | `design/brand/masters/bodyflow-wordmark.svg` | `57503318200bf68e5e76665675b6a8a7bf743f8ceb754e9599ec9754a9bf163d` |
| `horizontal` | `design/brand/masters/bodyflow-horizontal.svg` | `cb88d3af9c6687573f06c34349c9c8bda2e602f8862cc728ca564ed880708cb0` |
| `monochrome` | `design/brand/masters/bodyflow-symbol-monochrome.svg` | `6809439b3b5de85682665d65c26c9088159420eab55b92606878776501d6ce36` |
| `negative` | `design/brand/masters/bodyflow-symbol-negative.svg` | `a8f1ff09714181cb64d66c3bdf8481ec298d425adca514636c4ffd9d3eeb9647` |

## Checksums dos exports

| ID | Caminho | SHA-256 |
| --- | --- | --- |
| `symbol-vector` | `design/brand/exports/bodyflow-symbol.svg` | `01343fcb7aa4a52b303bb9a602180f13973c74d2b53704eaa817ce1b9a9f5eb9` |
| `symbol-png-44` | `design/brand/exports/bodyflow-symbol-44.png` | `d1fd4fb65559fd794b1a825a2da48e354011a4bb1551b87c42fccbe749cd7725` |
| `symbol-png-88` | `design/brand/exports/bodyflow-symbol-88.png` | `6221f43bf532380524cba828aabe50a75d88c3b658b346250f291c70b87e5f97` |
| `symbol-png-132` | `design/brand/exports/bodyflow-symbol-132.png` | `89eee28f8c122ac7188995a80fc46a8f04578e03f68548f7c568406d04fd29c0` |
| `symbol-png-512` | `design/brand/exports/bodyflow-symbol-512.png` | `d272fc80e6d0592e67aac29bb752fcd9f516024a6c9793bb18225130a93c3412` |
| `symbol-png-1024` | `design/brand/exports/bodyflow-symbol-1024.png` | `c1b3211e35b5e14345f90ed40ce26fadaec241bcf8ab621a0ddf0245749088e3` |
| `wordmark-vector` | `design/brand/exports/bodyflow-wordmark.svg` | `57503318200bf68e5e76665675b6a8a7bf743f8ceb754e9599ec9754a9bf163d` |
| `wordmark-png-320` | `design/brand/exports/bodyflow-wordmark-320.png` | `f30910270bbd82cc78359ee4b6bf857c8f69f48773a15555f1b540da007f754b` |
| `wordmark-png-640` | `design/brand/exports/bodyflow-wordmark-640.png` | `b324e888da5998fa7aa03b2cf1230ff5e7bda875ab53b2c314424c49cbd6e2e0` |
| `wordmark-png-960` | `design/brand/exports/bodyflow-wordmark-960.png` | `71690737047267eb3ac8891206538bb3e40f4cf41bd698fa1de909ec881fd5bc` |
| `horizontal-vector` | `design/brand/exports/bodyflow-horizontal.svg` | `cb88d3af9c6687573f06c34349c9c8bda2e602f8862cc728ca564ed880708cb0` |
| `horizontal-png-360` | `design/brand/exports/bodyflow-horizontal-360.png` | `36c11814729657d6c7194b23e9dcb7fc050c6c263f304fd489587ff802ed27d5` |
| `horizontal-png-720` | `design/brand/exports/bodyflow-horizontal-720.png` | `4510f7b318841b4a5f9760dc84e724b18dda7f17bd0b81ac22cccb6e790ccb8a` |
| `horizontal-png-1080` | `design/brand/exports/bodyflow-horizontal-1080.png` | `8019c4b6305d5a3468987ef27ae05ec914848fe4e1e1509db237a6547a45f105` |
| `monochrome-vector` | `design/brand/exports/bodyflow-symbol-monochrome.svg` | `6809439b3b5de85682665d65c26c9088159420eab55b92606878776501d6ce36` |
| `monochrome-png-44` | `design/brand/exports/bodyflow-monochrome-44.png` | `6677b8ae8b3a4fe152e48cf6b0e0999121d04e7dc1d9ff8a69213f82a0ab3807` |
| `monochrome-png-88` | `design/brand/exports/bodyflow-monochrome-88.png` | `8ef78c14517bc118282de9848e7572b0ec405136ead1fcda1a9cacbf3b2534a9` |
| `monochrome-png-132` | `design/brand/exports/bodyflow-monochrome-132.png` | `0c7ab08351e7d21e6a43f67591c4f2bf040f9a0a9dc030172bad06f4e0776f94` |
| `negative-vector` | `design/brand/exports/bodyflow-symbol-negative.svg` | `a8f1ff09714181cb64d66c3bdf8481ec298d425adca514636c4ffd9d3eeb9647` |
| `negative-png-44` | `design/brand/exports/bodyflow-negative-44.png` | `27954fd7666e1ba108a7f47e0f351df6c0136c0ef310b32bcc0cfaaba6d657da` |
| `negative-png-88` | `design/brand/exports/bodyflow-negative-88.png` | `a69f656631e3d88fb3e3a2f966a1c1848c92d02924a8364d08a15c1b4a05de8b` |
| `negative-png-132` | `design/brand/exports/bodyflow-negative-132.png` | `d99817a75434d5ceb752f86a5ac79b0a792d070603be655fc5ddf3ba22167729` |
| `launch-vector` | `design/brand/exports/bodyflow-launch.svg` | `06580ac994f24363ae04f767c0c9068043cae1a2d6af5946361b8e9ac2095e38` |
| `app-icon-default` | `design/brand/exports/bodyflow-app-icon-default-1024.png` | `400f0b86753226cc26e682b073689311d4086a50594b0f61e1b114d901d2dab8` |
| `app-icon-dark` | `design/brand/exports/bodyflow-app-icon-dark-1024.png` | `361e42e33a442a961a34d38b61847d88287424d210c17721068fae0c4b10c2fc` |
| `app-icon-tinted` | `design/brand/exports/bodyflow-app-icon-tinted-1024.png` | `10c3e7af9f15e4209c79002df05495d9709c3b1c4577ce1f94c129899cc04703` |
| `review-comparison` | `design/brand/exports/brand-comparison.png` | `822011b4478e1af322ab83c0be24d8d1a4fbbe27a57a03279cf7300822be64f4` |
| `review-reduced-sizes` | `design/brand/exports/brand-reduced-sizes.png` | `263b48460df5b12fd800ccaad55768d2a17c691b397f371ba67c80e0cf67f1e1` |
| `review-light-dark` | `design/brand/exports/brand-light-dark.png` | `cfca072081070b3cb94ceea8a6105c57d80bb64dceb45143e3dc740750c2d5c8` |

## Renderer e versões de pacote

Identidade canônica observada pelo `brand:render:check`:

- schema do renderer: 1;
- imagem base:
  `node@sha256:d649c27dae7ba0137b3cef5dd75baa422c08dc3d9e3fc0c23dfb172dc3cc6436`;
- plataforma/arquitetura: `linux/x64` (`linux/amd64` no build Docker);
- Node.js canônico: 22.23.2;
- Sharp: 0.34.5; `concurrency: 1`; SIMD habilitado;
- pacote `bodyflow-brand-canonical-renderer`: 1.0.0;
- pacote `@img/sharp-libvips-linux-x64`: 1.2.4;
- pacote workspace `@mpp/scripts`: 0.0.1;
- pnpm usado pelo gate: 10.33.2.

Versões nativas registradas pelo Sharp canônico:

```text
aom 3.13.1; archive 3.8.2; cairo 1.18.4; cgif 0.5.0;
exif 0.6.25; expat 2.7.3; ffi 3.5.2; fontconfig 2.17.1;
freetype 2.14.1; fribidi 1.0.16; glib 2.86.1; harfbuzz 12.1.0;
heif 1.20.2; highway 1.3.0; imagequant 2.4.1; lcms 2.17;
mozjpeg 0826579; pango 1.57.0; pixman 0.46.4; png 1.6.50;
proxy-libintl 0.5; rsvg 2.61.2; spng 0.7.4; tiff 4.7.1;
vips 8.17.3; webp 1.6.0; xml2 2.15.1; zlib-ng 2.2.5.
```

Pacotes de sistema canônicos:

```text
fontconfig 2.14.1-4; fontconfig-config 2.14.1-4;
fonts-liberation2 2.1.5-1; libbrotli1 1.0.9-2+b6;
libexpat1 2.5.0-1+deb12u2; libfontconfig1 2.14.1-4;
libfreetype6 2.12.1+dfsg-5+deb12u4; libpng16 1.6.39-2+deb12u5;
libxml2 2.9.14+dfsg-1.3~deb12u6;
libxml2-utils 2.9.14+dfsg-1.3~deb12u6.
```

Fontes canônicas: Liberation Sans Regular
`8d91388f1d3604b3b8ae0e3ee2d140e50cd6122f9214514f4aca772540a4076d`
e Bold
`ba0e0dc3f7aca5b0afbc31e800531ee43be3aa79ae35b2ef1f6470a9547765c4`.

Os testes de contrato e o validator rodaram no host Ubuntu 24.04.4 LTS,
kernel `6.8.0-137-generic`, arquitetura x86_64, Node.js 24.14.0 e pnpm
10.33.2. A renderização de comparação não usa esse Node host: usa apenas o
container canônico acima.

## Ambiente do gate nativo pré-freeze

O host Linux não oferece `xcodebuild` nem `swift`; a validação nativa foi
executada separadamente no Mac sobre o snapshot candidato pré-freeze, em uma
worktree temporária detached e limpa:

- SHA candidato pré-freeze validado:
  `a384ef66543790d219c606bb963cd4cb6312d0ac`;
- estado do manifesto nesse SHA: `1.0.0-candidate.1 / candidate`;
- path lógico: `/tmp/bodyflow-task5-native.r7XokT/worktree`;
- path físico: `/private/tmp/bodyflow-task5-native.r7XokT/worktree`;
- Xcode 26.6 (`17F113`);
- Swift 6.3.3 (`swiftlang-6.3.3.1.3`);
- macOS 26.5.2 (`25F84`);
- simulador: iPhone 17 Pro, iOS 26.5 (`23F77`), UDID
  `27291590-659D-4A29-8F45-CA5CA2D154F9`.

Depois desse gate, a promoção para `1.0.0 / approved` alterou somente
`brand_version` e `approval_state`. Os gates Linux pós-freeze e os fingerprints
invariantes provaram que não houve mudança em código iOS, assets ou Asset
Catalog entre o snapshot validado no Mac e o commit de aprovação.

### Testes nativos focados

O comando do brief terminou com exit 0 e `TEST SUCCEEDED`:

```sh
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/BodyFlowBrandAssetTests \
  -only-testing:BodyFlowTests/ScreenStateTests test
```

- total: 15 testes lógicos / 46 execuções;
- aprovadas: 46; falhas: 0; skips: 0; expected failures: 0;
- `ScreenStateTests`: 10 testes lógicos / 16 execuções;
- `BodyFlowBrandAssetTests`: 5 testes lógicos / 30 execuções.

Warnings observados nos testes, sem ocultação:

- AppIntents: 3 ocorrências;
- diagnostics herdados de isolamento MainActor em
  `HydrationRegistrationView.swift` (`text`, `date`) e
  `WorkoutRegistrationView.swift` (`selectedSegmentIndex`, `date`, `text`);
- resultado não usado de `waitUntilStarted` em
  `RegistrationSheetTaskCoordinatorTests.swift:68`: 7 ocorrências.

### Builds Debug e Release

```sh
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" build
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow -configuration Release \
  -destination "generic/platform=iOS Simulator" build
```

- Debug: exit 0, `BUILD SUCCEEDED`; AppIntents ×1, com extração de metadata
  ignorada porque não há dependency de `AppIntents.framework`;
- Release: exit 0, `BUILD SUCCEEDED`; AppIntents ×1; os mesmos 6 diagnostics
  herdados de isolamento MainActor foram compilados para arm64 e x86_64,
  totalizando 12 ocorrências;
- warnings Asset Catalog/`actool`: zero em testes, Debug e Release.

### Preservação da sessão Mac

A sessão Mac não editou nem rerenderizou o repositório. A worktree original
permaneceu em HEAD `03df789`; seus nove arquivos modificados foram preservados.
O porcelain inicial e final ficou byte-idêntico, com SHA-256
`4fc733aeb4f41ce17e7ed094920c0d5ab70da26b879d49c594a84f050e58550c`.
O staging permaneceu vazio; o estado `behind 1` decorreu somente de `fetch`.
Não houve edit, stage, commit, push, PR ou rerender na sessão Mac.

## Comandos e resultados

| Comando | Resultado observado em 2026-08-10 |
| --- | --- |
| `pnpm --filter @mpp/scripts brand:test` | exit 0; 46 testes, 46 passes, 0 failures/skips/todos |
| `pnpm --filter @mpp/scripts brand:validate` | exit 0; source 1491 × 1055 e SHA-256 aprovado; `errors: []` |
| `pnpm --filter @mpp/scripts brand:render:check` | exit 0; 26 outputs de produto e 3 reviews; `Canonical BodyFlow brand render is byte-identical.` |
| auditoria proibida abaixo | exit 0; zero matches em todas as sete classes |
| prova de invariância | 35/35 hashes de fonte/master/export; fingerprints declarado e físico idênticos ao baseline pré-aprovação; três evidências com `cmp` exit 0 |
| `git diff --check` | exit 0; nenhuma whitespace error; o README não rastreado também passou em `git diff --no-index --check` |
| testes Xcode focados no snapshot candidato pré-freeze `a384ef6…` | exit 0, `TEST SUCCEEDED`; 15 testes lógicos / 46 execuções; 46 aprovadas, 0 falhas/skips/expected failures |
| build Xcode Debug no snapshot candidato pré-freeze `a384ef6…` | exit 0, `BUILD SUCCEEDED` |
| build Xcode Release no snapshot candidato pré-freeze `a384ef6…` | exit 0, `BUILD SUCCEEDED` |

Todos os gates Linux da tabela foram rerodados após a promoção do manifesto
para `1.0.0 / approved`.

O `brand:render:check` foi executado somente em modo `--check`; nenhum render
host-native foi produzido e nenhum output aprovado foi substituído.

### Freeze pós-aprovação

O diff rastreado do manifesto contém exatamente duas substituições:

```text
brand_version: 1.0.0-candidate.1 -> 1.0.0
approval_state: candidate -> approved
```

- SHA-256 final do manifesto:
  `7f729f2221f95c6023fb98a01db4eae469c17568725eb96b6b5ead2ab2448b07`;
- fingerprint SHA-256 do bloco `{source,masters,exports}`, antes e depois:
  `ac0dfdf952416557f6420e083f0e7233b9eac54e24b6c320875fb5cabe821a76`;
- fingerprint SHA-256 físico de source + masters + exports + Asset Catalog,
  antes e depois:
  `468ce80310ade419cc6ea52dfe0a8a37c96740d6c6a3104c95c165de52852a6d`;
- 35/35 hashes declarados de source/master/export correspondem aos bytes;
- os três PNGs de evidência continuam byte-idênticos aos review exports;
- auditoria proibida final: sete classes, zero matches;
- allowlist final: manifesto, README e três evidências; `.gstack/` excluído;
- gate Mac aprovado sobre o snapshot candidato pré-freeze `a384ef6…`, com zero
  warning de Asset Catalog/`actool`; a promoção posterior de dois campos foi
  coberta pelos gates Linux/invariância, sem mudança em código iOS, assets ou
  catálogo; warnings herdados preservados no registro acima.

## Auditoria de conteúdo proibido

O escopo textual foi `design/brand` e
`apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets`, limitado a
SVG/XML/JSON. Raster foi inspecionado separadamente com ImageMagick, sem tratar
bytes comprimidos como texto. A busca Swift cobriu todo o target do app.

```sh
rg -n -i -P --glob '*.svg' --glob '*.xml' --glob '*.json' '(?:href|src)\s*=\s*["'\'' ]*(?:https?:)?//|url\(\s*["'\'' ]*https?://|"(?:url|uri|href|src)"\s*:\s*"https?://' design/brand apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets
rg -n -i -P --glob '*.svg' --glob '*.xml' --glob '*.json' '<script\b|javascript:|data:[^,;]+;base64|on(?:load|error|click)\s*=' design/brand apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets
rg -n -i -P --glob '*.svg' --glob '*.xml' --glob '*.json' '\b(?:api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|password|passwd|authorization|bearer)\b|-----BEGIN [A-Z ]+PRIVATE KEY-----|[[:alnum:]._%+-]+@[[:alnum:].-]+\.[A-Za-z]{2,}' design/brand apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets
rg -n -i -P --glob '*.svg' --glob '*.xml' --glob '*.json' '\b(?:Balu|MPP|CoreFlow|Cal[ _-]*AI)\b' design/brand apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets
rg -n -i -P --glob '*.svg' --glob '*.xml' --glob '*.json' '<text\b|font-family|@font-face|\b(?:pt-BR|en-US|tagline|slogan)\b' design/brand apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets
rg -n -P --glob '*.swift' '\b(?:Canvas|Path|CGPath|UIBezierPath)\s*(?:\{|\()|\b(?:addLine|addCurve|move)\s*\(to:' apps/ios/BodyFlow/BodyFlow
find design/brand apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets -type f -printf '%p\n' | rg -n -i -P '(?:balu|mpp|coreflow|cal[ _-]*ai|https?|base64|api[_-]?key|secret|password|token)'
```

Resultado final: zero referências externas, scripts/event handlers, payloads
base64, credenciais/PII, nomes concorrentes ou legados, texto localizado/live,
geometria de logo em Swift e nomes de arquivo proibidos. Cada `rg` retornou
exit 1 por ausência de correspondências; o wrapper fail-fast converteu esse
resultado esperado em sucesso do gate.

## Alpha, espaço de cor e metadata raster

Comando de inspeção:

```sh
find design/brand -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print0 | sort -z | xargs -0 identify -format '%i|%m|%wx%h|colorspace=%[colorspace]|channels=%[channels]|opaque=%[opaque]|comment=%c\n'
```

Resultado:

- fonte JPEG: sRGB, RGB opaco; perfil ICC de 456 bytes; sem comentário;
- símbolos, wordmarks, lockups horizontais e variantes monochrome/negative em
  PNG: sRGB com alpha transparente conforme manifesto;
- App Icons default/dark/tinted: 1024 × 1024, sRGB, RGB opaco;
- três review exports e três cópias de evidência: 1600 × 1000, sRGB, RGB
  opaco;
- nenhum comentário raster foi encontrado; fora o ICC da fonte, ImageMagick
  não reportou perfil, EXIF, IPTC, XMP ou label nos outputs.

Os SVGs são vetores path-only, sem `<text>`, fonte, script ou imagem externa.
O validator também confirmou dimensões e política de alpha de todo o conjunto.

## Limitações da comparação visual

- A fonte é um board JPEG rasterizado, não um master vetorial; comparação de
  pixels com os SVGs reconstruídos não é uma medida válida de fidelidade.
- Redimensionamento, antialiasing e composição de fundos nos boards de review
  podem alterar a aparência em relação ao zoom da fonte.
- Reprodutibilidade byte a byte comprova integridade do pipeline, não aprovação
  estética da silhueta, seta, gradientes ou wordmark.
- Os boards reduzido e Light/Dark são composições de revisão, não screenshots de
  um app nativo. O gate Mac confirma contratos e builds; não transforma esses
  boards em capturas pixel-perfect de runtime.
- O checkpoint deve comparar as três evidências diretamente com
  `design/brand/source/bodyflow-approved-board.jpg`.

## Aprovação humana

Status: **APROVADO VISUALMENTE**.

- Texto exato recebido: “Aprovo visualmente a família BodyFlow versão 1.0.0.”
- Data da aprovação humana: 2026-08-10.
- `brand_version` exata aprovada: `1.0.0`.
- `approval_state`: `approved`.

A aprovação cobre:

- [x] silhueta do símbolo e forma da seta;
- [x] gradientes e tratamento cromático;
- [x] geometria do wordmark;
- [x] lockup horizontal;
- [x] variantes monochrome e negative;
- [x] App Icon em tamanhos reduzidos;
- [x] composição de splash/launch;
- [x] contraste Light/Dark.

A aprovação acima encerra o checkpoint visual do Task 5. Qualquer revisão
visual futura deve abrir uma nova alteração controlada; não autoriza substituir
os outputs aprovados por render host-native.

## Itens atribuídos a incrementos posteriores

- mascote e animações: Motion And Illustration;
- strings `pt-BR` e `en-US`: String Catalog no Increment 3; nenhuma copy está
  embutida nos assets;
- aplicação dos assets em screens e motion: incrementos visuais posteriores;
- referências de onboarding de terceiros: apenas Increment 4 e nunca entram
  como artwork deste conjunto;
- Android: reutilização futura dos masters platform-neutral, com implementação
  separada;
- signing, deploy e TestFlight: fora deste gate.
