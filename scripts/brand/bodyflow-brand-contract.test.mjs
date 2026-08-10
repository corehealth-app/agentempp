import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

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
