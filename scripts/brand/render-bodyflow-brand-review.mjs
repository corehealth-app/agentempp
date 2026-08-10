import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

import { assertCanonicalBrandRenderer } from "./bodyflow-brand-renderer-contract.mjs";
import {
  atomicWrite,
  productExportAssets,
  reviewExportAssets,
  writeManifestExports,
} from "./render-bodyflow-brand-assets.mjs";

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultRepositoryRoot = path.resolve(moduleDirectory, "../..");
const manifestRelativePath = "design/brand/bodyflow-brand-assets.json";

export async function renderBodyFlowBrandReview(
  repositoryRoot = defaultRepositoryRoot,
) {
  assertCanonicalBrandRenderer();
  const root = path.resolve(repositoryRoot);
  const manifest = JSON.parse(
    await readFile(path.join(root, manifestRelativePath), "utf8"),
  );
  const source = await readFile(path.join(root, manifest.source.path));
  const symbol = await readFile(
    path.join(root, "design/brand/exports/bodyflow-symbol.svg"),
  );
  const horizontal = await readFile(
    path.join(root, "design/brand/exports/bodyflow-horizontal.svg"),
  );
  const monochrome = await readFile(
    path.join(root, "design/brand/exports/bodyflow-symbol-monochrome.svg"),
  );
  const negative = await readFile(
    path.join(root, "design/brand/exports/bodyflow-symbol-negative.svg"),
  );
  const defaultIcon = await readFile(
    path.join(root, "design/brand/exports/bodyflow-app-icon-default-1024.png"),
  );
  const darkIcon = await readFile(
    path.join(root, "design/brand/exports/bodyflow-app-icon-dark-1024.png"),
  );
  const tintedIcon = await readFile(
    path.join(root, "design/brand/exports/bodyflow-app-icon-tinted-1024.png"),
  );

  const boards = [
    await comparisonBoard(source, horizontal, symbol),
    await reducedSizesBoard(defaultIcon, darkIcon, tintedIcon),
    await lightDarkBoard(horizontal, monochrome, negative),
  ];
  for (const [index, asset] of reviewExportAssets.entries()) {
    await atomicWrite(path.join(root, asset.path), boards[index]);
  }
  await writeManifestExports(root, manifest, [
    ...productExportAssets,
    ...reviewExportAssets,
  ]);
  return { reviewCount: reviewExportAssets.length };
}

async function comparisonBoard(source, horizontal, symbol) {
  const sourcePanel = await sharp(source)
    .resize(700, 760, { fit: "contain", background: "#FFFFFF" })
    .flatten({ background: "#FFFFFF" })
    .png()
    .toBuffer();
  const horizontalPanel = await sharp(horizontal, { density: 216 })
    .resize(680, 240, { fit: "contain" })
    .png()
    .toBuffer();
  const symbolPanel = await sharp(symbol, { density: 216 })
    .resize(340, 340, { fit: "contain" })
    .png()
    .toBuffer();

  return board("Approved JPEG source", "Reconstructed vector family", [
    { input: sourcePanel, left: 60, top: 160 },
    { input: horizontalPanel, left: 850, top: 210 },
    { input: symbolPanel, left: 1020, top: 520 },
  ]);
}

async function reducedSizesBoard(defaultIcon, darkIcon, tintedIcon) {
  const sizes = [16, 20, 29, 40, 60, 76, 84, 128, 256];
  const composites = [];
  let x = 80;
  for (const size of sizes) {
    const preview = await sharp(defaultIcon)
      .resize(size, size)
      .png()
      .toBuffer();
    composites.push({ input: preview, left: x, top: 180 + 256 - size });
    composites.push({ input: label(String(size), Math.max(48, size)), left: x, top: 470 });
    x += Math.max(size, 110) + 35;
  }

  const appearances = [
    ["Default", defaultIcon],
    ["Dark", darkIcon],
    ["Tinted", tintedIcon],
  ];
  for (const [index, [name, icon]] of appearances.entries()) {
    composites.push({
      input: await sharp(icon).resize(180, 180).png().toBuffer(),
      left: 410 + index * 300,
      top: 650,
    });
    composites.push({
      input: textLabel(name, 180),
      left: 410 + index * 300,
      top: 850,
    });
  }

  return board(
    "App Icon reduced-size checks",
    "Default, dark, and tinted",
    composites,
  );
}

async function lightDarkBoard(horizontal, monochrome, negative) {
  const colored = await sharp(horizontal, { density: 216 })
    .resize(620, 220, { fit: "contain" })
    .png()
    .toBuffer();
  const mono = await sharp(monochrome, { density: 216 })
    .resize(220, 220, { fit: "contain" })
    .png()
    .toBuffer();
  const white = await sharp(negative, { density: 216 })
    .resize(220, 220, { fit: "contain" })
    .png()
    .toBuffer();

  const base = sharp({
    create: { width: 1600, height: 1000, channels: 3, background: "#F7F1E7" },
  });
  return base
    .composite([
      { input: colorPanel("#FFFFFF", 760, 400), left: 40, top: 100 },
      { input: colorPanel("#F7F1E7", 760, 400), left: 800, top: 100 },
      { input: colorPanel("#006C6A", 760, 400), left: 40, top: 520 },
      { input: colorPanel("#142C33", 760, 400), left: 800, top: 520 },
      { input: colored, left: 110, top: 190 },
      { input: mono, left: 1070, top: 180 },
      { input: white, left: 310, top: 610 },
      { input: white, left: 1070, top: 610 },
    ])
    .removeAlpha()
    .toColourspace("srgb")
    .png({ compressionLevel: 9, adaptiveFiltering: false })
    .toBuffer();
}

function board(leftTitle, rightTitle, composites) {
  return sharp({
    create: { width: 1600, height: 1000, channels: 3, background: "#F7F1E7" },
  })
    .composite([
      { input: heading(leftTitle, 620), left: 60, top: 65 },
      { input: heading(rightTitle, 620), left: 850, top: 65 },
      ...composites,
    ])
    .removeAlpha()
    .toColourspace("srgb")
    .png({ compressionLevel: 9, adaptiveFiltering: false })
    .toBuffer();
}

function heading(text, width) {
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="70">
  <text x="0" y="48" fill="#142C33" font-family="Arial, sans-serif" font-size="36" font-weight="700">${escapeXml(text)}</text>
</svg>`);
}

function label(text, width) {
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="48">
  <text x="0" y="30" fill="#142C33" font-family="Arial, sans-serif" font-size="22">${escapeXml(text)} px</text>
</svg>`);
}

function textLabel(text, width) {
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="48">
  <text x="${width / 2}" y="30" text-anchor="middle" fill="#142C33" font-family="Arial, sans-serif" font-size="22">${escapeXml(text)}</text>
</svg>`);
}

function colorPanel(color, width, height) {
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}">
  <rect width="${width}" height="${height}" rx="24" fill="${color}"/>
</svg>`);
}

function escapeXml(value) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

async function main() {
  const result = await renderBodyFlowBrandReview(defaultRepositoryRoot);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
