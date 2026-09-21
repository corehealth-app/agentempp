# Performe AI — Signal Spark — Assets RC1

## O que é esta entrega

Kit de arquivos vetoriais e raster derivados do Concept 3 escolhido pelo usuário.
Contém os 22 entregáveis obrigatórios listados pelo Codex e o AppIcon tinted condicional,
além de exports transparentes e materiais de revisão. Não é apenas uma prancha.

**Estado: CANDIDATO PARA APROVAÇÃO. Nenhum arquivo foi integrado ao app.**
A escolha anterior do conceito não constitui aprovação dos bytes desta reconstrução.

## Abra primeiro

`review/Performe_AI_Signal_Spark_Revisao_RC1.pdf` — cinco páginas: variantes,
ícones/escala reduzida, lockups, splash e comparação com a referência original.
`review/01-review.png` a `review/05-review.png` — as mesmas páginas em PNG.

## Reconstrução e limites

O P curvo e a estrela coral de quatro pontas foram reconstruídos com curvas Bézier.
As variantes usam uma única geometria; os preenchimentos mudam com o tema.
Os SVGs/PDFs de marca não contêm PNG incorporado. Os wordmarks são curvas, não texto
vinculado a uma fonte instalada. Gradientes foram simplificados e a versão escura foi
ajustada para leitura sobre teal. A referência raster original permanece byte-idêntica.
Não se alega identidade pixel a pixel nem recuperação de um vetor original inexistente.

O wordmark usa Inter Display Medium em contornos. É uma proposta de lettering para
aprovação, não uma alegação de identificação da fonte usada na imagem original.
Nenhuma fonte é distribuída. Não há mudança autorizada da fonte do app.

## Arquivos para integração posterior

- `masters/`: 11 SVGs vetoriais — 4 símbolos, 3 wordmarks e 4 lockups horizontais.
- `exports/`: os 6 PDFs exigidos, 5 PDFs auxiliares, PNGs transparentes de apoio,
  3 prévias de splash, 2 AppIcons obrigatórios e 1 AppIcon tinted condicional.
- `references/`: a prancha e o recorte de referência, intactos, somente para comparação.
- `asset-delivery-manifest.json`: lista, finalidade, dimensão e SHA-256 dos arquivos.
- `SHA256SUMS.txt`: checksums de todos os arquivos do pacote, exceto do próprio manifesto
  de checksums; o ZIP possui checksum externo informado na entrega.

O manifesto de entrega NÃO substitui `assets/brand/performe-ai-public-v1/manifest.json`
do repositório e não registra aprovação em nome do usuário.

## AppIcon

Os PNGs têm 1024 × 1024 px, sRGB, RGB opaco, sem texto e sem máscara de cantos gravada.
O símbolo fica dentro da zona central proposta. `tinted` é um candidato em escala de cinza;
a existência do arquivo não comprova suporte no pipeline iOS nem aprovação de uso.
Default e dark exigem aprovação separada. Tinted permanece pendente por padrão.

## Splash

Compact: 750 × 1334 (375 × 667 @2x).
Standard: 1179 × 2556 (393 × 852 @3x).
Large: 860 × 1864 (430 × 932 @2x).

Esses PNGs são REVISÃO DE COMPOSIÇÃO: não importar uma tela inteira como bitmap.
A UI deve usar símbolo/wordmark isolados e fundo nativo. Não foram adicionados slogans,
fotografia, ondas, barra de status, imagem de telefone ou espera artificial.

## Validação realizada nesta entrega

- presença dos 22 arquivos obrigatórios e do opcional;
- XML/SVG com curvas, sem raster/fonte externa/script;
- PDFs vetoriais sem objetos de imagem nem fontes dependentes;
- renderização dos PDFs em MuPDF;
- transparência real dos PNGs de símbolo/wordmark/lockup;
- dimensões, opacidade e escala de cinza dos ícones;
- dimensões das prévias de splash;
- preservação dos SHA-256 das duas referências;
- verificação de texto dentro das páginas do PDF de revisão.

Detalhes: `documentation/validation-report.json`.
Essa validação não equivale a aprovação visual humana, build no Xcode, importação nos
catálogos, teste de ícones no iOS, TestFlight ou rebrand completo.

## Aprovação necessária

Conferir símbolos, gradientes, espaço negativo, lettering, lockups e ícones no PDF.
Após aprovação explícita dos arquivos exatos, o Codex deve copiar os bytes aprovados,
sem redesenhar, vetorizar novamente ou regenerar a logo.
Não alterar assets BodyFlow históricos, bundle, signing, entitlements ou contratos.

O kit não traz validação jurídica de marca/domínio nem autorização para publicação.
Não há recursos remotos, contas QA, integrações, custos de provedor ou alterações no Git.
