import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

import { validateBrandContract } from "./bodyflow-brand-contract.mjs";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const manifestPath = path.join(
  repositoryRoot,
  "design/brand/bodyflow-brand-assets.json",
);
const expectedSourceHash =
  "af44d4b2036638720eaaf58c05fa6098f69b21c7639b91bb4a60bc85c64c15b7";
const requiredMasterIds = [
  "symbol",
  "wordmark",
  "horizontal",
  "monochrome",
  "negative",
];
const assetsCatalogPath = path.join(
  repositoryRoot,
  "apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets",
);
const expectedExportMatrix = [
  vectorExport("symbol-vector", "bodyflow-symbol.svg", "symbol"),
  ...squareRasterExports("symbol", [44, 88, 132, 512, 1024]),
  vectorExport("wordmark-vector", "bodyflow-wordmark.svg", "wordmark"),
  ...widthRasterExports("wordmark", [320, 640, 960], 960, 256),
  vectorExport("horizontal-vector", "bodyflow-horizontal.svg", "horizontal"),
  ...widthRasterExports("horizontal", [360, 720, 1080], 1536, 512),
  vectorExport(
    "monochrome-vector",
    "bodyflow-symbol-monochrome.svg",
    "monochrome",
  ),
  ...squareRasterExports("monochrome", [44, 88, 132]),
  vectorExport("negative-vector", "bodyflow-symbol-negative.svg", "negative"),
  ...squareRasterExports("negative", [44, 88, 132]),
  vectorExport("launch-vector", "bodyflow-launch.svg", "launch"),
  appIconExport("app-icon-default", "bodyflow-app-icon-default-1024.png"),
  appIconExport("app-icon-dark", "bodyflow-app-icon-dark-1024.png"),
  appIconExport("app-icon-tinted", "bodyflow-app-icon-tinted-1024.png"),
  reviewExport("review-comparison", "brand-comparison.png", 1600, 1000),
  reviewExport("review-reduced-sizes", "brand-reduced-sizes.png", 1600, 1000),
  reviewExport("review-light-dark", "brand-light-dark.png", 1600, 1000),
];

test("validates the immutable approved BodyFlow source", async () => {
  const result = await validateBrandContract(repositoryRoot);

  assert.equal(result.schemaVersion, 1);
  assert.equal(result.source.sha256, expectedSourceHash);
  assert.deepEqual(result.source.dimensions, { width: 1491, height: 1055 });
  assert.deepEqual(result.errors, []);
});

test("rejects a one-byte source mutation", async (context) => {
  const fixture = await createFixtureRoot(context);
  const sourcePath = path.join(
    fixture,
    "design/brand/source/bodyflow-approved-board.jpg",
  );
  const source = await readFile(sourcePath);
  source[source.length - 1] ^= 0x01;
  await writeFile(sourcePath, source);

  const result = await validateBrandContract(fixture);

  assert.match(result.errors.join("\n"), /source sha256 mismatch/i);
});

test("rejects a coordinated approved source and manifest rebaseline", async (context) => {
  const fixture = await createFixtureRoot(context);
  const fixtureManifestPath = path.join(
    fixture,
    "design/brand/bodyflow-brand-assets.json",
  );
  const sourcePath = path.join(
    fixture,
    "design/brand/source/bodyflow-approved-board.jpg",
  );
  const replacement = await sharp(await readFile(sourcePath))
    .resize(1490, 1055, { fit: "fill" })
    .jpeg({ quality: 90 })
    .toBuffer();
  const metadata = await sharp(replacement).metadata();
  const manifest = JSON.parse(await readFile(fixtureManifestPath, "utf8"));

  await writeFile(sourcePath, replacement);
  manifest.source.sha256 = createHash("sha256")
    .update(replacement)
    .digest("hex");
  manifest.source.width = metadata.width;
  manifest.source.height = metadata.height;
  manifest.source.color_space = "sRGB";
  await writeFile(fixtureManifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  const result = await validateBrandContract(fixture);
  const errors = result.errors.join("\n");

  assert.match(errors, /approved source sha256 mismatch/i);
  assert.match(errors, /approved source dimensions mismatch/i);
});

test("rejects rebaselining the approved source path or color-space declaration", async (context) => {
  const alternatePath = "design/brand/source/rebaselined-board.jpg";
  const fixture = await createFixtureRoot(context, (manifest) => ({
    ...manifest,
    source: {
      ...manifest.source,
      path: alternatePath,
      color_space: "srgb",
    },
  }));
  const approvedSource = await readFile(path.join(
    fixture,
    "design/brand/source/bodyflow-approved-board.jpg",
  ));
  const alternateAbsolutePath = path.join(fixture, alternatePath);
  await mkdir(path.dirname(alternateAbsolutePath), { recursive: true });
  await writeFile(alternateAbsolutePath, approvedSource);

  const result = await validateBrandContract(fixture);
  const errors = result.errors.join("\n");

  assert.match(errors, /approved source contract mismatch: path/i);
  assert.match(errors, /approved source contract mismatch: color_space/i);
});

test("rejects a declared export that is missing", async (context) => {
  const fixture = await createFixtureRoot(context, (manifest) => ({
    ...manifest,
    exports: [
      {
        id: "missing-export",
        path: "design/brand/exports/missing.png",
        sha256: "0".repeat(64),
      },
    ],
  }));

  const result = await validateBrandContract(fixture);

  assert.match(result.errors.join("\n"), /declared asset is missing/i);
});

test("rejects duplicate asset ids and paths", async (context) => {
  const fixture = await createFixtureRoot(context, (manifest) => ({
    ...manifest,
    masters: [
      {
        id: "symbol",
        path: "design/brand/masters/bodyflow-symbol.svg",
        sha256: "0".repeat(64),
      },
    ],
    exports: [
      {
        id: "symbol",
        path: "design/brand/masters/bodyflow-symbol.svg",
        sha256: "0".repeat(64),
      },
    ],
  }));

  const result = await validateBrandContract(fixture);
  const errors = result.errors.join("\n");

  assert.match(errors, /duplicate asset id/i);
  assert.match(errors, /duplicate asset path/i);
});

test("rejects an undeclared file below the exports directory", async (context) => {
  const fixture = await createFixtureRoot(context);
  const undeclaredPath = path.join(
    fixture,
    "design/brand/exports/undeclared.png",
  );
  await mkdir(path.dirname(undeclaredPath), { recursive: true });
  await writeFile(undeclaredPath, Buffer.from("not a production image"));

  const result = await validateBrandContract(fixture);

  assert.match(result.errors.join("\n"), /undeclared export/i);
});

test("rejects asset paths that escape the repository", async (context) => {
  const fixture = await createFixtureRoot(context, (manifest) => ({
    ...manifest,
    exports: [
      {
        id: "escape",
        path: "../outside.png",
        sha256: "0".repeat(64),
      },
    ],
  }));

  const result = await validateBrandContract(fixture);

  assert.match(result.errors.join("\n"), /path escapes repository/i);
});

test("rejects a noncanonical renderer declaration", async (context) => {
  const fixture = await createFixtureRoot(context, (manifest) => ({
    ...manifest,
    renderer: {
      ...manifest.renderer,
      node: "different",
    },
  }));

  const result = await validateBrandContract(fixture);

  assert.match(result.errors.join("\n"), /renderer contract mismatch: node/i);
});

test("rejects unexpected renderer declaration fields", async (context) => {
  const fixture = await createFixtureRoot(context, (manifest) => ({
    ...manifest,
    renderer: {
      ...manifest.renderer,
      unverifiedRuntime: "allowed-by-partial-comparison",
    },
  }));

  const result = await validateBrandContract(fixture);

  assert.match(
    result.errors.join("\n"),
    /renderer contract mismatch: unverifiedRuntime/i,
  );
});

test("rejects unexpected empty renderer declaration objects", async (context) => {
  const fixture = await createFixtureRoot(context, (manifest) => ({
    ...manifest,
    renderer: {
      ...manifest.renderer,
      unverifiedRuntime: {},
    },
  }));

  const result = await validateBrandContract(fixture);

  assert.match(
    result.errors.join("\n"),
    /renderer contract mismatch: unverifiedRuntime/i,
  );
});

test("rejects unexpected dotted renderer declaration keys", async (context) => {
  const fixture = await createFixtureRoot(context, (manifest) => ({
    ...manifest,
    renderer: {
      ...manifest.renderer,
      "sharp.aom": manifest.renderer.sharp.aom,
    },
  }));

  const result = await validateBrandContract(fixture);

  assert.match(
    result.errors.join("\n"),
    /renderer contract mismatch: sharp\.aom; unexpected field/i,
  );
});

test("rejects a self-consistent export hash rebaseline", async (context) => {
  const replacement = Buffer.from("replacement approved export bytes");
  const replacementHash = createHash("sha256").update(replacement).digest("hex");
  const originalManifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const originalExport = originalManifest.exports.find(
    (asset) => asset.id === "app-icon-default",
  );
  assert.ok(originalExport);

  const fixture = await createFixtureRoot(context, (manifest) => ({
    ...manifest,
    exports: [{ ...originalExport, sha256: replacementHash }],
  }));
  const replacementPath = path.join(fixture, originalExport.path);
  await mkdir(path.dirname(replacementPath), { recursive: true });
  await writeFile(replacementPath, replacement);

  const result = await validateBrandContract(fixture);

  assert.match(
    result.errors.join("\n"),
    /approved export sha256 mismatch: app-icon-default/i,
  );
});

test("rejects removal of an approved export baseline", async (context) => {
  const fixture = await createFixtureRoot(context, (manifest) => ({
    ...manifest,
    exports: manifest.exports.filter(
      (asset) => asset.id !== "app-icon-default",
    ),
  }));

  const result = await validateBrandContract(fixture);

  assert.match(
    result.errors.join("\n"),
    /approved export is missing: app-icon-default/i,
  );
});

test("declares the complete path-only SVG master family", async () => {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const result = await validateBrandContract(repositoryRoot);

  assert.deepEqual(
    manifest.masters.map((asset) => asset.id),
    requiredMasterIds,
  );
  assert.deepEqual(result.errors, []);
});

test("rejects live text and font declarations in an SVG master", async (context) => {
  const { root, replaceMaster } = await createSvgFixtureRoot(context);
  await replaceMaster(
    "wordmark",
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 256"><text x="0" y="180" font-family="Example Sans">BodyFlow</text></svg>\n',
  );

  const result = await validateBrandContract(root);
  const errors = result.errors.join("\n");

  assert.match(errors, /forbidden svg element <text>/i);
  assert.match(errors, /live font declaration/i);
});

test("rejects external images in an SVG master", async (context) => {
  const { root, replaceMaster } = await createSvgFixtureRoot(context);
  await replaceMaster(
    "symbol",
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><image href="https://example.invalid/logo.png" width="512" height="512"/></svg>\n',
  );

  const result = await validateBrandContract(root);
  const errors = result.errors.join("\n");

  assert.match(errors, /forbidden svg element <image>/i);
  assert.match(errors, /external svg reference/i);
});

test("rejects a prefixed SVG namespace that hides live text", async (context) => {
  const { root, replaceMaster } = await createSvgFixtureRoot(context);
  await replaceMaster(
    "wordmark",
    '<svg xmlns="http://www.w3.org/2000/svg" xmlns:s="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="#007C78" d="M64 256C128 64 384 64 448 256C384 448 128 448 64 256Z"/><s:text fill="#007C78">BodyFlow</s:text></svg>\n',
  );

  const result = await validateBrandContract(root);

  assert.match(
    result.errors.join("\n"),
    /prefixed SVG namespace|element outside the SVG allowlist/i,
  );
});

test("rejects UTF-16 SVG bytes that hide a document type declaration", async (context) => {
  const { root, replaceMaster } = await createSvgFixtureRoot(context);
  const xml = [
    '<?xml version="1.0" encoding="UTF-16"?>',
    '<!DOCTYPE svg [<!ENTITY brand "BodyFlow">]>',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">',
    '<path fill="#007C78" d="M64 256C128 64 384 64 448 256C384 448 128 448 64 256Z"/>',
    "</svg>",
  ].join("");
  const utf16 = Buffer.concat([
    Buffer.from([0xff, 0xfe]),
    Buffer.from(xml, "utf16le"),
  ]);
  await replaceMaster("symbol", utf16);

  const result = await validateBrandContract(root);

  assert.match(result.errors.join("\n"), /canonical UTF-8/i);
});

test("rejects noncanonical SVG paint syntax", async (context) => {
  const { root, replaceMaster } = await createSvgFixtureRoot(context);
  await replaceMaster(
    "symbol",
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="rgb(0, 124, 120)" d="M64 256C128 64 384 64 448 256C384 448 128 448 64 256Z"/></svg>\n',
  );

  const result = await validateBrandContract(root);

  assert.match(result.errors.join("\n"), /paint outside the SVG allowlist/i);
});

test("rejects SVG elements and attributes outside the positive allowlist", async (context) => {
  const { root, replaceMaster } = await createSvgFixtureRoot(context);
  await replaceMaster(
    "symbol",
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="#007C78" onclick="alert(1)" d="M64 256C128 64 384 64 448 256C384 448 128 448 64 256Z"/><circle fill="#007C78" cx="256" cy="256" r="32"/></svg>\n',
  );

  const result = await validateBrandContract(root);
  const errors = result.errors.join("\n");

  assert.match(errors, /element outside the SVG allowlist/i);
  assert.match(errors, /attribute outside the SVG allowlist/i);
});

test("rejects fixed dimensions, undeclared colors, and missing path geometry", async (context) => {
  const { root, replaceMaster } = await createSvgFixtureRoot(context);
  await replaceMaster(
    "horizontal",
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 512" width="1280" height="512"><rect width="1280" height="512" fill="#123456"/></svg>\n',
  );

  const result = await validateBrandContract(root);
  const errors = result.errors.join("\n");

  assert.match(errors, /must not declare width or height/i);
  assert.match(errors, /color is not declared in manifest palette/i);
  assert.match(errors, /must contain outlined path geometry/i);
});

test("declares the exact deterministic production export matrix", async () => {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));

  assert.deepEqual(
    manifest.exports.map(({ sha256: _sha256, ...asset }) => asset),
    expectedExportMatrix,
  );
  for (const asset of manifest.exports) {
    assert.match(asset.sha256, /^[0-9a-f]{64}$/);
  }
});

test("renders production PNGs with exact dimensions, sRGB, and alpha policy", async () => {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const rasterExports = manifest.exports.filter(
    (asset) => asset.media_type === "image/png",
  );

  assert.ok(rasterExports.length > 0, "expected raster exports");
  for (const asset of rasterExports) {
    const metadata = await sharp(path.join(repositoryRoot, asset.path)).metadata();
    assert.equal(metadata.format, "png", asset.id);
    assert.equal(metadata.width, asset.width, asset.id);
    assert.equal(metadata.height, asset.height, asset.id);
    assert.equal(metadata.space, "srgb", asset.id);
    assert.equal(metadata.hasAlpha, asset.alpha === "transparent", asset.id);
  }
});

test("populates six vector image sets with explicit rendering intent", async () => {
  const expectedImageSets = [
    ["BodyFlowSymbol", "bodyflow-symbol.svg", "original"],
    ["BodyFlowWordmark", "bodyflow-wordmark.svg", "original"],
    ["BodyFlowHorizontal", "bodyflow-horizontal.svg", "original"],
    ["BodyFlowMonochrome", "bodyflow-symbol-monochrome.svg", "template"],
    ["BodyFlowNegative", "bodyflow-symbol-negative.svg", "template"],
    ["BodyFlowLaunch", "bodyflow-launch.svg", "original"],
  ];

  for (const [name, filename, intent] of expectedImageSets) {
    const imageSetPath = path.join(assetsCatalogPath, `${name}.imageset`);
    const contents = JSON.parse(
      await readFile(path.join(imageSetPath, "Contents.json"), "utf8"),
    );
    assert.deepEqual(contents.images, [{ filename, idiom: "universal" }], name);
    assert.equal(contents.properties["preserves-vector-representation"], true, name);
    assert.equal(contents.properties["template-rendering-intent"], intent, name);
    const vector = await readFile(path.join(imageSetPath, filename));
    assert.ok(vector.length > 0, name);
  }
});

test("populates opaque default, dark, and tinted App Icons plus semantic accents", async () => {
  const appIcon = JSON.parse(
    await readFile(
      path.join(assetsCatalogPath, "AppIcon.appiconset/Contents.json"),
      "utf8",
    ),
  );
  assert.deepEqual(
    appIcon.images.map(({ filename, appearances }) => ({ filename, appearances })),
    [
      {
        filename: "bodyflow-app-icon-default-1024.png",
        appearances: undefined,
      },
      {
        filename: "bodyflow-app-icon-dark-1024.png",
        appearances: [{ appearance: "luminosity", value: "dark" }],
      },
      {
        filename: "bodyflow-app-icon-tinted-1024.png",
        appearances: [{ appearance: "luminosity", value: "tinted" }],
      },
    ],
  );

  const accents = JSON.parse(
    await readFile(
      path.join(assetsCatalogPath, "AccentColor.colorset/Contents.json"),
      "utf8",
    ),
  );
  assert.deepEqual(
    accents.colors.map((entry) => ({
      appearance: entry.appearances?.[0]?.value ?? "light",
      components: entry.color.components,
    })),
    [
      {
        appearance: "light",
        components: { alpha: "1.000", blue: "0.403922", green: "0.427451", red: "0.000000" },
      },
      {
        appearance: "dark",
        components: { alpha: "1.000", blue: "0.478431", green: "0.686275", red: "0.831373" },
      },
    ],
  );
});

async function createFixtureRoot(context, transform = (manifest) => manifest) {
  const root = await mkdtemp(path.join(tmpdir(), "bodyflow-brand-contract-"));
  context.after(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const sourceRelativePath = "design/brand/source/bodyflow-approved-board.jpg";
  const source = await readFile(path.join(repositoryRoot, sourceRelativePath));
  const fixtureSourcePath = path.join(root, sourceRelativePath);
  await mkdir(path.dirname(fixtureSourcePath), { recursive: true });
  await writeFile(fixtureSourcePath, source);

  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const fixtureManifest = transform(structuredClone(manifest));
  const fixtureManifestPath = path.join(
    root,
    "design/brand/bodyflow-brand-assets.json",
  );
  await mkdir(path.dirname(fixtureManifestPath), { recursive: true });
  await writeFile(
    fixtureManifestPath,
    `${JSON.stringify(fixtureManifest, null, 2)}\n`,
  );

  assert.equal(createHash("sha256").update(source).digest("hex"), expectedSourceHash);
  return root;
}

async function createSvgFixtureRoot(context) {
  const root = await createFixtureRoot(context);
  const fixtureManifestPath = path.join(
    root,
    "design/brand/bodyflow-brand-assets.json",
  );
  const manifest = JSON.parse(await readFile(fixtureManifestPath, "utf8"));
  const definitions = new Map(
    requiredMasterIds.map((id) => [
      id,
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="#007C78" d="M64 256C128 64 384 64 448 256C384 448 128 448 64 256Z"/></svg>\n`,
    ]),
  );

  manifest.palette = {
    teal: "#007C78",
    aqua: "#65D2C4",
    coral: "#FF735F",
    gold: "#D5A15D",
    ink: "#142C33",
    white: "#FFFFFF",
  };
  manifest.masters = requiredMasterIds.map((id) => ({
    id,
    path: `design/brand/masters/bodyflow-${id === "monochrome" || id === "negative" ? `symbol-${id}` : id}.svg`,
    sha256: hashText(definitions.get(id)),
    view_box: "0 0 512 512",
    role: id,
    contains_text: false,
  }));

  for (const master of manifest.masters) {
    const absolutePath = path.join(root, master.path);
    await mkdir(path.dirname(absolutePath), { recursive: true });
    await writeFile(absolutePath, definitions.get(master.id));
  }
  await writeFile(fixtureManifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  return {
    root,
    replaceMaster: async (id, contents) => {
      const current = JSON.parse(await readFile(fixtureManifestPath, "utf8"));
      const master = current.masters.find((asset) => asset.id === id);
      assert.ok(master, `missing fixture master ${id}`);
      await writeFile(path.join(root, master.path), contents);
      master.sha256 = hashText(contents);
      await writeFile(fixtureManifestPath, `${JSON.stringify(current, null, 2)}\n`);
    },
  };
}

function hashText(value) {
  return createHash("sha256").update(value).digest("hex");
}

function vectorExport(id, filename, role) {
  return {
    id,
    path: `design/brand/exports/${filename}`,
    media_type: "image/svg+xml",
    role,
    alpha: "vector",
    color_space: "sRGB",
  };
}

function squareRasterExports(role, sizes) {
  return sizes.map((size) => ({
    id: `${role}-png-${size}`,
    path: `design/brand/exports/bodyflow-${role}-${size}.png`,
    media_type: "image/png",
    role,
    width: size,
    height: size,
    alpha: "transparent",
    color_space: "sRGB",
  }));
}

function widthRasterExports(role, widths, sourceWidth, sourceHeight) {
  return widths.map((width) => ({
    id: `${role}-png-${width}`,
    path: `design/brand/exports/bodyflow-${role}-${width}.png`,
    media_type: "image/png",
    role,
    width,
    height: Math.round((width * sourceHeight) / sourceWidth),
    alpha: "transparent",
    color_space: "sRGB",
  }));
}

function appIconExport(id, filename) {
  return {
    id,
    path: `design/brand/exports/${filename}`,
    media_type: "image/png",
    role: "app_icon",
    width: 1024,
    height: 1024,
    alpha: "opaque",
    color_space: "sRGB",
  };
}

function reviewExport(id, filename, width, height) {
  return {
    id,
    path: `design/brand/exports/${filename}`,
    media_type: "image/png",
    role: "review",
    width,
    height,
    alpha: "opaque",
    color_space: "sRGB",
  };
}
