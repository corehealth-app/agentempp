import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

import { betterAheadPreservedAssets } from "./better-ahead-preserved-assets.mjs";

const runFile = promisify(execFile);
const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const betterAheadManifestPath = "design/brand/better-ahead-brand-assets.json";
const historicalManifestPath = "design/brand/bodyflow-brand-assets.json";
const historicalManifestSha256 =
  "7f729f2221f95c6023fb98a01db4eae469c17568725eb96b6b5ead2ab2448b07";
const catalogRoot =
  "apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets";
const expectedPreserved = new Map([
  ["design/brand/source/bodyflow-approved-board.jpg", "af44d4b2036638720eaaf58c05fa6098f69b21c7639b91bb4a60bc85c64c15b7"],
  ["design/brand/masters/bodyflow-symbol.svg", "01343fcb7aa4a52b303bb9a602180f13973c74d2b53704eaa817ce1b9a9f5eb9"],
  ["design/brand/exports/bodyflow-symbol.svg", "01343fcb7aa4a52b303bb9a602180f13973c74d2b53704eaa817ce1b9a9f5eb9"],
  ["design/brand/exports/bodyflow-symbol-44.png", "d1fd4fb65559fd794b1a825a2da48e354011a4bb1551b87c42fccbe749cd7725"],
  ["design/brand/exports/bodyflow-symbol-88.png", "6221f43bf532380524cba828aabe50a75d88c3b658b346250f291c70b87e5f97"],
  ["design/brand/exports/bodyflow-symbol-132.png", "89eee28f8c122ac7188995a80fc46a8f04578e03f68548f7c568406d04fd29c0"],
  ["design/brand/exports/bodyflow-symbol-512.png", "d272fc80e6d0592e67aac29bb752fcd9f516024a6c9793bb18225130a93c3412"],
  ["design/brand/exports/bodyflow-symbol-1024.png", "c1b3211e35b5e14345f90ed40ce26fadaec241bcf8ab621a0ddf0245749088e3"],
  ["design/brand/masters/bodyflow-symbol-monochrome.svg", "6809439b3b5de85682665d65c26c9088159420eab55b92606878776501d6ce36"],
  ["design/brand/exports/bodyflow-symbol-monochrome.svg", "6809439b3b5de85682665d65c26c9088159420eab55b92606878776501d6ce36"],
  ["design/brand/exports/bodyflow-monochrome-44.png", "6677b8ae8b3a4fe152e48cf6b0e0999121d04e7dc1d9ff8a69213f82a0ab3807"],
  ["design/brand/exports/bodyflow-monochrome-88.png", "8ef78c14517bc118282de9848e7572b0ec405136ead1fcda1a9cacbf3b2534a9"],
  ["design/brand/exports/bodyflow-monochrome-132.png", "0c7ab08351e7d21e6a43f67591c4f2bf040f9a0a9dc030172bad06f4e0776f94"],
  ["design/brand/masters/bodyflow-symbol-negative.svg", "a8f1ff09714181cb64d66c3bdf8481ec298d425adca514636c4ffd9d3eeb9647"],
  ["design/brand/exports/bodyflow-symbol-negative.svg", "a8f1ff09714181cb64d66c3bdf8481ec298d425adca514636c4ffd9d3eeb9647"],
  ["design/brand/exports/bodyflow-negative-44.png", "27954fd7666e1ba108a7f47e0f351df6c0136c0ef310b32bcc0cfaaba6d657da"],
  ["design/brand/exports/bodyflow-negative-88.png", "a69f656631e3d88fb3e3a2f966a1c1848c92d02924a8364d08a15c1b4a05de8b"],
  ["design/brand/exports/bodyflow-negative-132.png", "d99817a75434d5ceb752f86a5ac79b0a792d070603be655fc5ddf3ba22167729"],
  ["design/brand/exports/bodyflow-app-icon-default-1024.png", "400f0b86753226cc26e682b073689311d4086a50594b0f61e1b114d901d2dab8"],
  ["design/brand/exports/bodyflow-app-icon-dark-1024.png", "361e42e33a442a961a34d38b61847d88287424d210c17721068fae0c4b10c2fc"],
  ["design/brand/exports/bodyflow-app-icon-tinted-1024.png", "10c3e7af9f15e4209c79002df05495d9709c3b1c4577ce1f94c129899cc04703"],
  [`${catalogRoot}/AppIcon.appiconset/bodyflow-app-icon-default-1024.png`, "400f0b86753226cc26e682b073689311d4086a50594b0f61e1b114d901d2dab8"],
  [`${catalogRoot}/AppIcon.appiconset/bodyflow-app-icon-dark-1024.png`, "361e42e33a442a961a34d38b61847d88287424d210c17721068fae0c4b10c2fc"],
  [`${catalogRoot}/AppIcon.appiconset/bodyflow-app-icon-tinted-1024.png`, "10c3e7af9f15e4209c79002df05495d9709c3b1c4577ce1f94c129899cc04703"],
]);

test("historical approved manifest is the only baseline", async () => {
  const audit = await betterAheadPreservedAssets(repositoryRoot);

  assert.equal(audit.historicalBrandVersion, "1.0.0");
  assert.equal(audit.historicalApprovalState, "approved");
  assert.equal(audit.historicalManifest.path, historicalManifestPath);
  assert.equal(audit.historicalManifest.expectedSha256, historicalManifestSha256);
  assert.equal(audit.historicalManifest.committedSha256, historicalManifestSha256);
  assert.equal(audit.historicalManifest.physicalSha256, historicalManifestSha256);
  assert.equal(audit.mismatches.length, 0);
});

test("every preserved source, symbol export, and App Icon copy keeps its full hash", async () => {
  const audit = await betterAheadPreservedAssets(repositoryRoot);
  const actual = new Map(
    audit.preserved.map((asset) => [asset.historicalPath, asset]),
  );

  assert.equal(actual.size, expectedPreserved.size);
  for (const [historicalPath, expectedHash] of expectedPreserved) {
    const asset = actual.get(historicalPath);
    assert.ok(asset, historicalPath);
    assert.equal(asset.classification, "preserved", historicalPath);
    assert.equal(asset.historicalSha256, expectedHash, historicalPath);
    assert.equal(asset.committedSha256, expectedHash, historicalPath);
    assert.equal(asset.physicalSha256, expectedHash, historicalPath);
  }
});

test("wordmark lockups are never classified as preserved", async () => {
  const audit = await betterAheadPreservedAssets(repositoryRoot);

  assert.deepEqual(
    audit.intentionalNewRoles.toSorted(),
    ["horizontal", "launch", "wordmark"],
  );
  assert.equal(
    audit.preserved.some(({ role }) =>
      ["horizontal", "launch", "wordmark"].includes(role)),
    false,
  );
  assert.deepEqual(audit.newAssets, []);
});

test("every future catalog alias is semantic and product-neutral", async () => {
  const audit = await betterAheadPreservedAssets(repositoryRoot);
  const aliases = audit.preserved
    .flatMap(({ neutralCatalogPath }) => neutralCatalogPath ? [neutralCatalogPath] : []);

  assert.deepEqual(aliases.toSorted(), [
    `${catalogRoot}/AppIcon.appiconset/bodyflow-app-icon-dark-1024.png`,
    `${catalogRoot}/AppIcon.appiconset/bodyflow-app-icon-default-1024.png`,
    `${catalogRoot}/AppIcon.appiconset/bodyflow-app-icon-tinted-1024.png`,
    `${catalogRoot}/BrandMonochrome.imageset/brand-symbol-monochrome.svg`,
    `${catalogRoot}/BrandNegative.imageset/brand-symbol-negative.svg`,
    `${catalogRoot}/BrandSymbol.imageset/brand-symbol.svg`,
  ]);
  for (const alias of aliases) {
    assert.doesNotMatch(path.basename(path.dirname(alias)), /bodyflow|better-ahead/i, alias);
  }
});

test("catalog mode requires every preserved semantic bundle source", async () => {
  const audit = await betterAheadPreservedAssets(repositoryRoot, {
    requireCatalog: true,
  });

  assert.match(audit.mismatches.join("\n"), /BrandSymbol\.imageset.*missing/i);
  assert.match(audit.mismatches.join("\n"), /BrandMonochrome\.imageset.*missing/i);
  assert.match(audit.mismatches.join("\n"), /BrandNegative\.imageset.*missing/i);
  assert.doesNotMatch(audit.mismatches.join("\n"), /AppIcon\.appiconset.*sha256 mismatch/i);
});

test("catalog mode verifies preserved and approved new semantic sets", async (context) => {
  const fixture = await cloneFixture(context);
  await prepareCompleteCatalog(fixture);

  const audit = await betterAheadPreservedAssets(fixture, {
    requireCatalog: true,
  });

  assert.deepEqual(audit.mismatches, []);
});

test("catalog mode rejects missing, extra, misnamed, and re-encoded files", async (context) => {
  const cases = [
    {
      name: "missing",
      async mutate(root) {
        await rm(path.join(root, catalogRoot, "BrandNegative.imageset/brand-symbol-negative.svg"));
      },
      pattern: /BrandNegative\.imageset.*missing/i,
    },
    {
      name: "extra",
      async mutate(root) {
        await writeFile(path.join(root, catalogRoot, "BrandSymbol.imageset/extra.svg"), "extra\n");
      },
      pattern: /BrandSymbol\.imageset.*extra|missing, extra, or misnamed/i,
    },
    {
      name: "misnamed",
      async mutate(root) {
        const directory = path.join(root, catalogRoot, "BrandWordmark.imageset");
        await rename(
          path.join(directory, "better-ahead-wordmark.svg"),
          path.join(directory, "wrong-name.svg"),
        );
      },
      pattern: /BrandWordmark\.imageset.*missing|missing, extra, or misnamed/i,
    },
    {
      name: "re-encoded",
      async mutate(root) {
        const payload = path.join(root, catalogRoot, "BrandSymbol.imageset/brand-symbol.svg");
        await writeFile(payload, Buffer.concat([await readFile(payload), Buffer.from("\n")]));
      },
      pattern: /sha256 mismatch.*BrandSymbol\.imageset/i,
    },
  ];

  for (const fixtureCase of cases) {
    const fixture = await cloneFixture(context);
    await prepareCompleteCatalog(fixture);
    await fixtureCase.mutate(fixture);
    const audit = await betterAheadPreservedAssets(fixture, {
      requireCatalog: true,
    });
    assert.match(audit.mismatches.join("\n"), fixtureCase.pattern, fixtureCase.name);
  }
});

test("fails closed for missing or unapproved historical manifest state", async (context) => {
  const missingFixture = await cloneFixture(context);
  await mutateJson(missingFixture, betterAheadManifestPath, (manifest) => ({
    ...manifest,
    historical_manifest: {
      ...manifest.historical_manifest,
      path: "design/brand/missing-approved-manifest.json",
    },
  }));
  const missingAudit = await betterAheadPreservedAssets(missingFixture);
  assert.match(missingAudit.mismatches.join("\n"), /historical manifest path/i);

  const unapprovedFixture = await cloneFixture(context);
  await mutateJson(unapprovedFixture, historicalManifestPath, (manifest) => ({
    ...manifest,
    approval_state: "candidate",
  }));
  const unapprovedAudit = await betterAheadPreservedAssets(unapprovedFixture);
  assert.match(unapprovedAudit.mismatches.join("\n"), /physical sha256/i);
  assert.match(unapprovedAudit.mismatches.join("\n"), /approval state/i);
});

test("rejects diagnostic paths, wildcard allowances, and expected-hash rebaselines", async (context) => {
  const cases = [
    {
      name: "diagnostic path",
      mutate(manifest) {
        manifest.preserved[0].historical_path =
          "/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1/diagnostic.png";
      },
      pattern: /repository-relative|diagnostic path/i,
    },
    {
      name: "wildcard path",
      mutate(manifest) {
        manifest.preserved[0].historical_path = "design/brand/exports/*.png";
      },
      pattern: /wildcard/i,
    },
    {
      name: "changed expected hash",
      mutate(manifest) {
        manifest.preserved[0].historical_sha256 = "0".repeat(64);
      },
      pattern: /historical sha256/i,
    },
  ];

  for (const fixtureCase of cases) {
    const fixture = await cloneFixture(context);
    await mutateJson(fixture, betterAheadManifestPath, (manifest) => {
      fixtureCase.mutate(manifest);
      return manifest;
    });
    const audit = await betterAheadPreservedAssets(fixture);
    assert.match(audit.mismatches.join("\n"), fixtureCase.pattern, fixtureCase.name);
  }
});

async function cloneFixture(context) {
  const fixture = path.join(
    tmpdir(),
    `better-ahead-preserved-${process.pid}-${Math.random().toString(16).slice(2)}`,
  );
  await runFile("git", ["clone", "--quiet", "--shared", repositoryRoot, fixture]);
  await copyFile(
    path.join(repositoryRoot, betterAheadManifestPath),
    path.join(fixture, betterAheadManifestPath),
  );
  context.after(async () => {
    await rm(fixture, { recursive: true, force: true });
  });
  return fixture;
}

async function mutateJson(root, relativePath, transform) {
  const absolutePath = path.join(root, relativePath);
  const value = JSON.parse(await readFile(absolutePath, "utf8"));
  await writeFile(absolutePath, `${JSON.stringify(transform(value), null, 2)}\n`);
}

async function prepareCompleteCatalog(root) {
  const manifest = JSON.parse(
    await readFile(path.join(root, betterAheadManifestPath), "utf8"),
  );
  for (const asset of manifest.preserved) {
    if (!asset.neutral_catalog_path
      || asset.neutral_catalog_path.includes("/AppIcon.appiconset/")) continue;
    await writeImageSet(
      root,
      asset.neutral_catalog_path,
      await readFile(path.join(root, asset.historical_path)),
      ["monochrome", "negative"].includes(asset.role) ? "template" : "original",
    );
  }

  const newAssets = [
    ["wordmark", "better-ahead-wordmark.svg", "BrandWordmark.imageset"],
    ["horizontal", "better-ahead-horizontal.svg", "BrandLogoHorizontal.imageset"],
    ["launch", "better-ahead-launch.svg", "BrandLaunch.imageset"],
  ].map(([role, filename, imageSet]) => {
    const bytes = Buffer.from(`<svg data-role="${role}"/>\n`);
    return {
      role,
      path: `design/brand/better-ahead/exports/${filename}`,
      sha256: createHash("sha256").update(bytes).digest("hex"),
      neutral_catalog_path: `${catalogRoot}/${imageSet}/${filename}`,
      bytes,
    };
  });
  for (const asset of newAssets) {
    const source = path.join(root, asset.path);
    await mkdir(path.dirname(source), { recursive: true });
    await writeFile(source, asset.bytes);
    await writeImageSet(root, asset.neutral_catalog_path, asset.bytes, "original");
  }
  manifest.new_assets = newAssets.map(({ bytes, ...asset }) => asset);
  await writeFile(
    path.join(root, betterAheadManifestPath),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
}

async function writeImageSet(root, relativePayloadPath, bytes, intent) {
  const absolutePayloadPath = path.join(root, relativePayloadPath);
  await mkdir(path.dirname(absolutePayloadPath), { recursive: true });
  await writeFile(absolutePayloadPath, bytes);
  await writeFile(
    path.join(path.dirname(absolutePayloadPath), "Contents.json"),
    `${JSON.stringify({
      images: [{ filename: path.basename(relativePayloadPath), idiom: "universal" }],
      info: { author: "xcode", version: 1 },
      properties: {
        "preserves-vector-representation": true,
        "template-rendering-intent": intent,
      },
    }, null, 2)}\n`,
  );
}
