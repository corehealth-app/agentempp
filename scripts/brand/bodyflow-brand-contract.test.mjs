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
