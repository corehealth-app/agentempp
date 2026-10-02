import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import { scanSurface } from "./premium-surface-scan.mjs";

const catalogPath = path.join(
  "apps", "ios", "BodyFlow", "BodyFlow", "Resources", "Localizable.xcstrings",
);
const assetsPath = path.join(
  "apps", "ios", "BodyFlow", "BodyFlow", "Resources", "Assets.xcassets",
);

function plist(entries) {
  const body = Object.entries(entries)
    .map(([key, value]) => `  <key>${key}</key>\n  <string>${value}</string>`)
    .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>\n${body}\n</dict></plist>\n`;
}

function catalog(overrides = {}) {
  const values = {
    "product.name": { pt: "Performe AI", en: "Performe AI" },
    "assistant.name": { pt: "Flow", en: "Flow" },
    "welcome.message": { pt: "Bem-vindo", en: "Welcome" },
    ...overrides,
  };
  return {
    sourceLanguage: "pt-BR",
    strings: Object.fromEntries(Object.entries(values).map(([key, value]) => [
      key,
      {
        localizations: {
          "pt-BR": { stringUnit: { state: "translated", value: value.pt } },
          en: { stringUnit: { state: "translated", value: value.en } },
        },
      },
    ])),
    version: "1.0",
  };
}

function writeCompiledStrings(appPath, sourceCatalog) {
  for (const language of ["pt-BR", "en"]) {
    const values = Object.fromEntries(
      Object.entries(sourceCatalog.strings).map(([key, entry]) => [
        key,
        entry.localizations[language].stringUnit.value,
      ]),
    );
    const directory = path.join(appPath, `${language}.lproj`);
    mkdirSync(directory, { recursive: true });
    writeFileSync(path.join(directory, "Localizable.strings"), plist(values));
  }
}

function createFixture(t, beforeCommit) {
  const root = mkdtempSync(path.join(tmpdir(), "premium-surface-scan-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const sourceCatalog = catalog();
  const absoluteCatalog = path.join(root, catalogPath);
  mkdirSync(path.dirname(absoluteCatalog), { recursive: true });
  writeFileSync(absoluteCatalog, JSON.stringify(sourceCatalog));

  const historicalAsset = path.join(root, assetsPath, "Historical.imageset", "historical.svg");
  mkdirSync(path.dirname(historicalAsset), { recursive: true });
  writeFileSync(historicalAsset, "historical-brand-bytes");
  writeFileSync(
    path.join(path.dirname(historicalAsset), "Contents.json"),
    JSON.stringify({ images: [{ filename: "historical.svg", idiom: "universal" }], info: { version: 1, author: "xcode" } }),
  );

  // Optionally seed extra baseline (historical) content before the commit so a
  // test can model catalog state without tripping the unapproved-new-asset gate.
  if (typeof beforeCommit === "function") beforeCommit(root);

  execFileSync("git", ["init", "-q"], { cwd: root });
  execFileSync("git", ["config", "user.name", "QA"], { cwd: root });
  execFileSync("git", ["config", "user.email", "qa@example.invalid"], { cwd: root });
  execFileSync("git", ["add", "."], { cwd: root });
  execFileSync("git", ["commit", "-qm", "fixture baseline"], { cwd: root });
  const baseline = execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();

  const appPath = path.join(root, "Build", "Performe AI.app");
  mkdirSync(appPath, { recursive: true });
  writeFileSync(path.join(appPath, "Info.plist"), plist({
    CFBundleIdentifier: "com.bodyflow.app",
    CFBundleDisplayName: "Performe AI",
    CFBundleName: "Performe AI",
    CFBundleExecutable: "PerformeAI",
  }));
  writeCompiledStrings(appPath, sourceCatalog);
  writeFileSync(path.join(appPath, "Assets.car"), "compiled-historical-assets");
  writeFileSync(path.join(appPath, "PerformeAI"), "com.bodyflow.app\0BodyFlow\0Performe AI\0Flow\0");

  return {
    root,
    appPath,
    baseline,
    historicalAsset,
    sourceCatalog,
    compiledAssetNames: ["Historical"],
  };
}

function run(fixture, overrides = {}) {
  return scanSurface({
    appPath: fixture.appPath,
    repoRoot: fixture.root,
    baseline: fixture.baseline,
    compiledAssetNames: fixture.compiledAssetNames,
    ...overrides,
  });
}


const stagingBundleIdentifier = "com.performeai.app.dev.k6942zjtv6";

function writeFixtureBundleIdentifier(fixture, identifier) {
  writeFileSync(path.join(fixture.appPath, "Info.plist"), plist({
    CFBundleIdentifier: identifier,
    CFBundleDisplayName: "Performe AI",
    CFBundleName: "Performe AI",
    CFBundleExecutable: "PerformeAI",
  }));
}

test("accepts the exact staging bundle only when explicitly expected", (t) => {
  const fixture = createFixture(t);
  writeFixtureBundleIdentifier(fixture, stagingBundleIdentifier);
  const result = run(fixture, { expectedBundleIdentifier: stagingBundleIdentifier });
  assert.equal(result.status, "PASS");
  assert.equal(result.compiled.bundleIdentifier, stagingBundleIdentifier);
  assert.equal(result.compiled.expectedBundleIdentifier, stagingBundleIdentifier);
  assert.equal(result.classifications.PUBLIC_LEAK, 0);
});

test("keeps the canonical bundle strict by default for a staging artifact", (t) => {
  const fixture = createFixture(t);
  writeFixtureBundleIdentifier(fixture, stagingBundleIdentifier);
  const result = run(fixture);
  assert.equal(result.status, "FAIL");
  assert.ok(result.failures.some((failure) => failure.code === "UNEXPECTED_BUNDLE_IDENTIFIER"));
});

test("rejects a staging artifact whose explicitly expected bundle differs", (t) => {
  const fixture = createFixture(t);
  writeFixtureBundleIdentifier(fixture, stagingBundleIdentifier);
  const result = run(fixture, { expectedBundleIdentifier: "com.performeai.app.dev.other" });
  assert.equal(result.status, "FAIL");
  assert.ok(result.failures.some((failure) => failure.code === "UNEXPECTED_BUNDLE_IDENTIFIER"));
});

test("CLI applies explicit staging identity and preserves default and mismatch rejection", (t) => {
  const fixture = createFixture(t);
  writeFixtureBundleIdentifier(fixture, stagingBundleIdentifier);
  // The fixture Assets.car is synthetic. Keep this CLI test deterministic by
  // substituting only assetutil metadata, matching run()'s existing injected names.
  const bin = path.join(fixture.root, "fixture-bin");
  mkdirSync(bin);
  writeFileSync(path.join(bin, "xcrun"), `#!/usr/bin/env node
if (process.argv[2] !== "assetutil" || process.argv[3] !== "--info"
    || process.argv[4] !== ${JSON.stringify(path.join(fixture.appPath, "Assets.car"))}) process.exit(99);
process.stdout.write(${JSON.stringify(JSON.stringify(fixture.compiledAssetNames.map((Name) => ({ Name }))))});
`, { mode: 0o755 });
  const sourceScript = fileURLToPath(new URL("./premium-surface-scan.mjs", import.meta.url));
  const script = path.join(fixture.root, "scripts", "uiux", "premium-surface-scan.mjs");
  mkdirSync(path.dirname(script), { recursive: true });
  writeFileSync(script, readFileSync(sourceScript));
  for (const [expected, accepted] of [
    [stagingBundleIdentifier, true],
    [undefined, false],
    ["com.performeai.app.dev.other", false],
  ]) {
    const args = [realpathSync(script), "--app", fixture.appPath, "--baseline", fixture.baseline];
    if (expected !== undefined) args.push("--expected-bundle-id", expected);
    const result = spawnSync(process.execPath, args, {
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}${path.delimiter}${path.dirname(process.execPath)}${path.delimiter}${process.env.PATH ?? ""}` },
    });
    assert.equal(result.status, accepted ? 0 : 1);
    assert.equal(result.stderr, "");
    const output = JSON.parse(result.stdout);
    assert.equal(output.compiled.bundleIdentifier, stagingBundleIdentifier);
    assert.equal(output.compiled.expectedBundleIdentifier, expected ?? "com.bodyflow.app");
    assert.equal(output.status, accepted ? "PASS" : "FAIL");
    if (!accepted) {
      assert.ok(output.failures.some((failure) => failure.code === "UNEXPECTED_BUNDLE_IDENTIFIER"));
    }
  }
});

test("accepts approved public identity and explicitly allowlisted technical BodyFlow", (t) => {
  const fixture = createFixture(t);
  const result = run(fixture);
  assert.equal(result.status, "PASS");
  assert.equal(result.classifications.PUBLIC_LEAK, 0);
  assert.ok(result.classifications.ALLOWED_TECHNICAL > 0);
  assert.equal(result.brandAssetApprovalGate, "PENDING_EXTERNAL_ASSETS");
});

for (const legacy of [
  "Uso do BodyFlow",
  "BodyFlow",
  "Dr. Roberto",
  "Dr Robert",
  "MPP",
]) {
  test(`rejects public legacy copy: ${legacy}`, (t) => {
    const fixture = createFixture(t);
    const badCatalog = catalog({ legacy: { pt: legacy, en: legacy } });
    writeFileSync(path.join(fixture.root, catalogPath), JSON.stringify(badCatalog));
    writeCompiledStrings(fixture.appPath, badCatalog);
    const result = run(fixture);
    assert.equal(result.status, "FAIL");
    assert.ok(result.failures.some((failure) => failure.code === "PUBLIC_LEGACY_COPY"));
  });
}

test("rejects a new unapproved asset", (t) => {
  const fixture = createFixture(t);
  const added = path.join(fixture.root, assetsPath, "PerformeFinal.imageset");
  mkdirSync(added, { recursive: true });
  writeFileSync(path.join(added, "Contents.json"), "{}");
  writeFileSync(path.join(added, "performe-final.svg"), "unapproved-new-bytes");
  const result = run(fixture);
  assert.equal(result.status, "FAIL");
  assert.ok(result.failures.some((failure) => failure.code === "UNAPPROVED_NEW_ASSET"));
});

test("accepts a checksum-exact catalog resource listed by the approved brand manifest", (t) => {
  const fixture = createFixture(t);
  const catalogDirectory = path.join(fixture.root, assetsPath, "PerformeAISymbolLightV1.imageset");
  const approvedBytes = "approved-signal-spark-vector";
  mkdirSync(catalogDirectory, { recursive: true });
  writeFileSync(path.join(catalogDirectory, "performe-ai-symbol-light.pdf"), approvedBytes);
  writeFileSync(
    path.join(catalogDirectory, "Contents.json"),
    JSON.stringify({
      images: [{ filename: "performe-ai-symbol-light.pdf", idiom: "universal" }],
      info: { version: 1, author: "xcode" },
      properties: { "preserves-vector-representation": true, "template-rendering-intent": "original" },
    }),
  );

  const familyRoot = path.join(fixture.root, "assets", "brand", "performe-ai-public-v1");
  const sourcePath = "exports/symbol-light.pdf";
  mkdirSync(path.join(familyRoot, "exports"), { recursive: true });
  writeFileSync(path.join(familyRoot, sourcePath), approvedBytes);
  writeFileSync(path.join(familyRoot, "manifest.json"), JSON.stringify({
    schemaVersion: 1,
    family: "performe-ai-public-v1",
    approvalStatus: "approved",
    approval: { reference: "approvals/rc1-user-approval.json" },
    approvedFiles: [{ path: sourcePath, sha256: "a0f57f068c59c24c13984de49b482595a737b663e2b33c9c13b4b0e8b5cc6e6f" }],
    catalogAssets: [{
      resourceName: "PerformeAISymbolLightV1",
      catalogPath: `${assetsPath}/PerformeAISymbolLightV1.imageset`,
      files: [{
        sourcePath,
        catalogFilename: "performe-ai-symbol-light.pdf",
        sha256: "a0f57f068c59c24c13984de49b482595a737b663e2b33c9c13b4b0e8b5cc6e6f",
      }],
    }],
  }));
  fixture.compiledAssetNames.push("PerformeAISymbolLightV1");

  const result = run(fixture);
  assert.equal(result.status, "PASS");
  assert.equal(result.brandAssetApprovalGate, "APPROVED_FOR_LISTED_RC1_FILES");
  assert.equal(result.counts.approvedNewAssetFiles, 2);
});

test("rejects a manifest-listed catalog resource when its bytes drift", (t) => {
  const fixture = createFixture(t);
  const catalogDirectory = path.join(fixture.root, assetsPath, "PerformeAISymbolLightV1.imageset");
  mkdirSync(catalogDirectory, { recursive: true });
  writeFileSync(path.join(catalogDirectory, "performe-ai-symbol-light.pdf"), "drifted-bytes");
  writeFileSync(path.join(catalogDirectory, "Contents.json"), "{}");
  const familyRoot = path.join(fixture.root, "assets", "brand", "performe-ai-public-v1");
  mkdirSync(path.join(familyRoot, "exports"), { recursive: true });
  writeFileSync(path.join(familyRoot, "exports", "symbol-light.pdf"), "approved-signal-spark-vector");
  writeFileSync(path.join(familyRoot, "manifest.json"), JSON.stringify({
    schemaVersion: 1,
    family: "performe-ai-public-v1",
    approvalStatus: "approved",
    approval: { reference: "approvals/rc1-user-approval.json" },
    approvedFiles: [{
      path: "exports/symbol-light.pdf",
      sha256: "a0f57f068c59c24c13984de49b482595a737b663e2b33c9c13b4b0e8b5cc6e6f",
    }],
    catalogAssets: [{
      resourceName: "PerformeAISymbolLightV1",
      catalogPath: `${assetsPath}/PerformeAISymbolLightV1.imageset`,
      files: [{
        sourcePath: "exports/symbol-light.pdf",
        catalogFilename: "performe-ai-symbol-light.pdf",
        sha256: "a0f57f068c59c24c13984de49b482595a737b663e2b33c9c13b4b0e8b5cc6e6f",
      }],
    }],
  }));

  const result = run(fixture);
  assert.equal(result.status, "FAIL");
  assert.ok(result.failures.some((failure) => failure.code === "APPROVED_ASSET_HASH_MISMATCH"));
});

test("project selects only the approved default and dark AppIcon catalog", () => {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
  const project = readFileSync(
    path.join(repoRoot, "apps", "ios", "BodyFlow", "BodyFlow.xcodeproj", "project.pbxproj"),
    "utf8",
  );
  const selections = [...project.matchAll(/ASSETCATALOG_COMPILER_APPICON_NAME = ([^;]+);/g)]
    .map((match) => match[1]);
  assert.ok(selections.length > 0);
  assert.deepEqual([...new Set(selections)], ["PerformeAIAppIconV1"]);
});

function seedAppIconSets(root, names) {
  for (const name of names) {
    const dir = path.join(root, assetsPath, `${name}.appiconset`);
    mkdirSync(dir, { recursive: true });
    writeFileSync(
      path.join(dir, "Contents.json"),
      JSON.stringify({ images: [], info: { version: 1, author: "xcode" } }),
    );
  }
}

function writeInfoPlistWithPrimaryIcon(appPath, primaryIconName) {
  writeFileSync(path.join(appPath, "Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.bodyflow.app</string>
  <key>CFBundleDisplayName</key><string>Performe AI</string>
  <key>CFBundleName</key><string>Performe AI</string>
  <key>CFBundleExecutable</key><string>PerformeAI</string>
  <key>CFBundleIcons</key><dict>
    <key>CFBundlePrimaryIcon</key><dict>
      <key>CFBundleIconName</key><string>${primaryIconName}</string>
    </dict>
  </dict>
</dict></plist>
`);
}

test("tolerates a non-designated appiconset omitted from the compiled catalog", (t) => {
  const fixture = createFixture(t, (root) => {
    seedAppIconSets(root, ["LegacyAppIcon", "PerformeAIAppIconV1"]);
  });
  // The designated primary icon compiles; the legacy appiconset is dropped by
  // actool and must not be reported as a missing compiled asset.
  writeInfoPlistWithPrimaryIcon(fixture.appPath, "PerformeAIAppIconV1");
  fixture.compiledAssetNames = ["Historical", "PerformeAIAppIconV1"];
  const result = run(fixture);
  assert.equal(result.status, "PASS");
  assert.ok(!result.failures.some((failure) => failure.code === "MISSING_COMPILED_NAMED_ASSET"));
});

test("still requires the designated primary appicon to compile", (t) => {
  const fixture = createFixture(t, (root) => {
    seedAppIconSets(root, ["LegacyAppIcon", "PerformeAIAppIconV1"]);
  });
  writeInfoPlistWithPrimaryIcon(fixture.appPath, "PerformeAIAppIconV1");
  // Designated icon absent from the compiled catalog must still fail.
  fixture.compiledAssetNames = ["Historical"];
  const result = run(fixture);
  assert.equal(result.status, "FAIL");
  assert.ok(result.failures.some(
    (failure) => failure.code === "MISSING_COMPILED_NAMED_ASSET" && failure.name === "PerformeAIAppIconV1",
  ));
});

test("rejects modified historical asset bytes", (t) => {
  const fixture = createFixture(t);
  writeFileSync(fixture.historicalAsset, "modified-historical-brand-bytes");
  const result = run(fixture);
  assert.equal(result.status, "FAIL");
  assert.ok(result.failures.some((failure) => failure.code === "HISTORICAL_ASSET_CHANGED"));
});

test("rejects a nonempty Assets.car without the named historical resource", (t) => {
  const fixture = createFixture(t);
  const result = run(fixture, { compiledAssetNames: [] });
  assert.equal(result.status, "FAIL");
  assert.ok(result.failures.some((failure) => failure.code === "MISSING_COMPILED_NAMED_ASSET"));
});

test("rejects a public BodyFlow literal outside the localization catalog", (t) => {
  const fixture = createFixture(t);
  const source = path.join(
    fixture.root,
    "apps", "ios", "BodyFlow", "BodyFlow", "Features", "PublicLeak.swift",
  );
  mkdirSync(path.dirname(source), { recursive: true });
  writeFileSync(source, 'import SwiftUI\nstruct PublicLeak: View { var body: some View { Text("BodyFlow secret-canary") } }\n');
  const result = run(fixture);
  assert.equal(result.status, "FAIL");
  const failure = result.failures.find((candidate) => candidate.code === "PUBLIC_LEGACY_SOURCE_COPY");
  assert.ok(failure);
  assert.deepEqual(Object.keys(failure).sort(), ["code", "path"]);
  assert.doesNotMatch(JSON.stringify(result), /secret-canary/);
});

test("rejects a missing catalog language", (t) => {
  const fixture = createFixture(t);
  const invalid = catalog();
  delete invalid.strings["welcome.message"].localizations.en;
  writeFileSync(path.join(fixture.root, catalogPath), JSON.stringify(invalid));
  const result = run(fixture);
  assert.equal(result.status, "FAIL");
  assert.ok(result.failures.some((failure) => failure.code === "MISSING_LOCALIZATION"));
});

test("rejects a Debug Flow fixture marker in the Release bundle", (t) => {
  const fixture = createFixture(t);
  writeFileSync(path.join(fixture.appPath, "PerformeAI"), "--ui-testing-flow-longHistory\0QA_REPLY_VISIBLE\0");
  const result = run(fixture);
  assert.equal(result.status, "FAIL");
  assert.ok(result.failures.some((failure) => failure.code === "DEBUG_FIXTURE_IN_RELEASE"));
});

test("fails closed for a missing app path", (t) => {
  const fixture = createFixture(t);
  fixture.appPath = path.join(fixture.root, "missing.app");
  assert.throws(() => run(fixture), /app path/i);
});

test("CLI returns sanitized JSON and a nonzero status for invalid input", (t) => {
  const fixture = createFixture(t);
  const script = fileURLToPath(new URL("./premium-surface-scan.mjs", import.meta.url));
  const result = spawnSync(process.execPath, [
    script,
    "--app", path.join(fixture.root, "missing.app"),
    "--baseline", fixture.baseline,
  ], { encoding: "utf8" });
  assert.equal(result.status, 1);
  assert.equal(result.stderr, "");
  const output = JSON.parse(result.stdout);
  assert.equal(output.status, "FAIL");
  assert.deepEqual(Object.keys(output).sort(), ["failures", "schemaVersion", "status"]);
  assert.equal(output.failures[0].code, "INPUT_OR_SCAN_ERROR");
  assert.match(output.failures[0].detail, /app path/i);
});

test("fails closed for an invalid catalog", (t) => {
  const fixture = createFixture(t);
  writeFileSync(path.join(fixture.root, catalogPath), "not-json");
  assert.throws(() => run(fixture), /catalog/i);
});

test("an empty compiled scan cannot succeed", (t) => {
  const fixture = createFixture(t);
  rmSync(fixture.appPath, { recursive: true, force: true });
  mkdirSync(fixture.appPath, { recursive: true });
  writeFileSync(path.join(fixture.appPath, "Info.plist"), plist({
    CFBundleIdentifier: "com.bodyflow.app",
    CFBundleDisplayName: "Performe AI",
    CFBundleExecutable: "PerformeAI",
  }));
  const result = run(fixture);
  assert.equal(result.status, "FAIL");
  assert.ok(result.failures.some((failure) => failure.code === "EMPTY_COMPILED_SCAN"));
});
