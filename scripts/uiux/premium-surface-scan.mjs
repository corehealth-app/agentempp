#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultRepoRoot = path.resolve(scriptDirectory, "../..");
const catalogRelativePath = path.join(
  "apps", "ios", "BodyFlow", "BodyFlow", "Resources", "Localizable.xcstrings",
);
const assetsRelativePath = path.join(
  "apps", "ios", "BodyFlow", "BodyFlow", "Resources", "Assets.xcassets",
);
const brandFamilyRelativePath = path.join("assets", "brand", "performe-ai-public-v1");
const brandManifestRelativePath = path.join(brandFamilyRelativePath, "manifest.json");
const requiredLanguages = ["pt-BR", "en"];
const debugFixtureMarkers = [
  "--ui-testing-flow-",
  "QA_REPLY_VISIBLE",
  "QA_END_OF_LONG_RESPONSE",
  "FlowPreviewRepository",
];
const technicalLegacyPatterns = [
  /com\.bodyflow\.app/gi,
  /\bBodyFlow(?:Tests|UITests|App)\b/g,
  /\bBodyFlow[A-Z][A-Za-z0-9_]*\b/g,
  /\$s\d+BodyFlow/g,
  /BodyFlow\//g,
  /BodyFlow(?:Symbol|Wordmark|Horizontal|Monochrome|Negative|Launch)/g,
];
const publicLegacyPatterns = [
  /\bBody\s*Flow\b/gi,
  /\bDr\.?\s*(?:Roberto|Robert)\b/gi,
  /\bMPP\b/g,
];

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function relative(root, target) {
  return path.relative(root, target).split(path.sep).join("/");
}

function filesRecursively(root) {
  if (!existsSync(root)) return [];
  const entries = readdirSync(root, { withFileTypes: true });
  return entries.flatMap((entry) => {
    const absolute = path.join(root, entry.name);
    return entry.isDirectory() ? filesRecursively(absolute) : [absolute];
  });
}

function run(command, args, options = {}) {
  return execFileSync(command, args, {
    encoding: options.encoding ?? "utf8",
    maxBuffer: 64 * 1024 * 1024,
    ...options,
  });
}

function readPlist(file) {
  try {
    return JSON.parse(run("plutil", ["-convert", "json", "-o", "-", file]));
  } catch {
    throw new Error(`invalid plist: ${path.basename(file)}`);
  }
}

function readCatalog(file) {
  try {
    const value = JSON.parse(readFileSync(file, "utf8"));
    if (!value?.strings || typeof value.strings !== "object") throw new Error();
    return value;
  } catch {
    throw new Error("invalid localization catalog");
  }
}

function occurrences(text, patterns) {
  return patterns.reduce((total, pattern) => {
    pattern.lastIndex = 0;
    return total + Array.from(text.matchAll(pattern)).length;
  }, 0);
}

function containsPublicLegacy(text) {
  return publicLegacyPatterns.some((pattern) => {
    pattern.lastIndex = 0;
    return pattern.test(text);
  });
}

function listBaselineAssets(repoRoot, baseline) {
  try {
    run("git", ["cat-file", "-e", `${baseline}^{commit}`], { cwd: repoRoot });
    const output = run(
      "git",
      ["ls-tree", "-r", "--name-only", baseline, "--", assetsRelativePath],
      { cwd: repoRoot },
    );
    return output.split("\n").filter(Boolean).sort();
  } catch {
    throw new Error("invalid baseline revision");
  }
}

function inspectApprovedBrandCatalog({ repoRoot, failures }) {
  const manifestPath = path.join(repoRoot, brandManifestRelativePath);
  if (!existsSync(manifestPath)) {
    return { gate: "PENDING_EXTERNAL_ASSETS", allowedFiles: new Map() };
  }

  let manifest;
  try {
    manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  } catch {
    failures.push({ code: "INVALID_BRAND_ASSET_MANIFEST", path: brandManifestRelativePath });
    return { gate: "INVALID_BRAND_ASSET_MANIFEST", allowedFiles: new Map() };
  }

  if (manifest.approvalStatus !== "approved") {
    return { gate: "PENDING_EXTERNAL_ASSETS", allowedFiles: new Map() };
  }
  if (
    typeof manifest.approval?.reference !== "string"
    || !manifest.approval.reference.startsWith("approvals/")
    || !Array.isArray(manifest.approvedFiles)
    || !Array.isArray(manifest.catalogAssets)
    || manifest.catalogAssets.length === 0
  ) {
    failures.push({ code: "INVALID_BRAND_ASSET_MANIFEST", path: brandManifestRelativePath });
    return { gate: "INVALID_BRAND_ASSET_MANIFEST", allowedFiles: new Map() };
  }

  const approvedHashes = new Map();
  for (const file of manifest.approvedFiles) {
    if (
      typeof file?.path !== "string"
      || !/^[a-f0-9]{64}$/.test(file?.sha256 ?? "")
      || file.path.toLowerCase().includes("tinted")
    ) {
      failures.push({ code: "INVALID_BRAND_ASSET_MANIFEST", path: brandManifestRelativePath });
      continue;
    }
    approvedHashes.set(file.path, file.sha256);
    const approvedSource = path.join(repoRoot, brandFamilyRelativePath, file.path);
    if (!existsSync(approvedSource)) {
      failures.push({ code: "APPROVED_ASSET_SOURCE_MISSING", path: file.path });
    } else if (sha256(readFileSync(approvedSource)) !== file.sha256) {
      failures.push({ code: "APPROVED_ASSET_SOURCE_HASH_MISMATCH", path: file.path });
    }
  }

  const allowedFiles = new Map();
  for (const asset of manifest.catalogAssets) {
    const catalogPath = asset?.catalogPath;
    if (
      typeof asset?.resourceName !== "string"
      || typeof catalogPath !== "string"
      || !catalogPath.startsWith(`${assetsRelativePath}/`)
      || catalogPath.toLowerCase().includes("tinted")
      || !Array.isArray(asset.files)
      || asset.files.length === 0
    ) {
      failures.push({ code: "INVALID_BRAND_ASSET_MANIFEST", path: brandManifestRelativePath });
      continue;
    }

    allowedFiles.set(`${catalogPath}/Contents.json`, null);
    for (const file of asset.files) {
      const approvedHash = approvedHashes.get(file?.sourcePath);
      if (
        typeof file?.catalogFilename !== "string"
        || file.catalogFilename.includes("/")
        || file.catalogFilename.toLowerCase().includes("tinted")
        || file?.sha256 !== approvedHash
      ) {
        failures.push({ code: "INVALID_BRAND_ASSET_MANIFEST", path: brandManifestRelativePath });
        continue;
      }
      allowedFiles.set(`${catalogPath}/${file.catalogFilename}`, file.sha256);
    }
  }

  return { gate: "APPROVED_FOR_LISTED_RC1_FILES", allowedFiles };
}

function inspectAssets({ repoRoot, baseline, failures, classifications }) {
  const assetRoot = path.join(repoRoot, assetsRelativePath);
  if (!existsSync(assetRoot)) throw new Error("asset catalog path is missing");
  const baselineFiles = listBaselineAssets(repoRoot, baseline);
  if (baselineFiles.length === 0) throw new Error("baseline asset catalog is empty");
  const currentFiles = filesRecursively(assetRoot)
    .map((file) => relative(repoRoot, file))
    .sort();
  const baselineSet = new Set(baselineFiles);
  const currentSet = new Set(currentFiles);
  const assets = [];
  const approvedCatalog = inspectApprovedBrandCatalog({ repoRoot, failures });
  let approvedNewAssetFiles = 0;

  for (const file of baselineFiles) {
    const baselineBytes = run("git", ["show", `${baseline}:${file}`], {
      cwd: repoRoot,
      encoding: null,
    });
    const currentPath = path.join(repoRoot, file);
    const currentBytes = existsSync(currentPath) ? readFileSync(currentPath) : null;
    const baselineHash = sha256(baselineBytes);
    const currentHash = currentBytes ? sha256(currentBytes) : null;
    const status = currentHash === baselineHash ? "IDENTICAL" : "CHANGED";
    assets.push({ path: file, baselineHash, currentHash, status });
    classifications.HISTORICAL_ASSET += 1;
    if (!currentSet.has(file)) {
      failures.push({ code: "HISTORICAL_ASSET_REMOVED", path: file });
    } else if (status !== "IDENTICAL") {
      failures.push({ code: "HISTORICAL_ASSET_CHANGED", path: file });
    }
  }

  for (const file of currentFiles) {
    if (!baselineSet.has(file)) {
      if (!approvedCatalog.allowedFiles.has(file)) {
        failures.push({ code: "UNAPPROVED_NEW_ASSET", path: file });
        continue;
      }
      approvedNewAssetFiles += 1;
      const expectedHash = approvedCatalog.allowedFiles.get(file);
      if (expectedHash && sha256(readFileSync(path.join(repoRoot, file))) !== expectedHash) {
        failures.push({ code: "APPROVED_ASSET_HASH_MISMATCH", path: file });
      }
    }
  }

  for (const file of approvedCatalog.allowedFiles.keys()) {
    if (!currentSet.has(file)) {
      failures.push({ code: "APPROVED_ASSET_MISSING", path: file });
    }
  }

  return { historical: assets, approvedNewAssetFiles, approvalGate: approvedCatalog.gate };
}

function inspectCatalog({ repoRoot, failures, classifications }) {
  const catalogPath = path.join(repoRoot, catalogRelativePath);
  if (!existsSync(catalogPath)) throw new Error("localization catalog path is missing");
  const catalog = readCatalog(catalogPath);
  const entries = Object.entries(catalog.strings);
  if (entries.length === 0) throw new Error("localization catalog is empty");
  let localizedValueCount = 0;
  let hasProduct = false;
  let hasAssistant = false;

  for (const [key, entry] of entries) {
    for (const language of requiredLanguages) {
      const value = entry?.localizations?.[language]?.stringUnit?.value;
      if (typeof value !== "string" || value.length === 0) {
        failures.push({ code: "MISSING_LOCALIZATION", key, language });
        continue;
      }
      localizedValueCount += 1;
      hasProduct ||= value.includes("Performe AI");
      hasAssistant ||= value === "Flow" || /\bFlow\b/.test(value);
      if (containsPublicLegacy(value)) {
        failures.push({ code: "PUBLIC_LEGACY_COPY", path: catalogRelativePath, key, language });
        classifications.PUBLIC_LEAK += 1;
      }
    }
  }
  if (!hasProduct) failures.push({ code: "MISSING_PUBLIC_PRODUCT_IDENTITY", path: catalogRelativePath });
  if (!hasAssistant) failures.push({ code: "MISSING_PUBLIC_ASSISTANT_IDENTITY", path: catalogRelativePath });
  return { catalog, keyCount: entries.length, localizedValueCount };
}

function inspectPublicSource({ repoRoot, failures, classifications }) {
  const sourceRoot = path.join(repoRoot, "apps", "ios", "BodyFlow", "BodyFlow");
  if (!existsSync(sourceRoot)) throw new Error("production source path is missing");
  const publicLiteral = /(?:Text|Label|Button|navigationTitle|accessibilityLabel)\s*\(\s*(?:verbatim:\s*)?"((?:[^"\\]|\\.)*)"/g;
  let inspectedLiterals = 0;

  for (const file of filesRecursively(sourceRoot).filter((candidate) => candidate.endsWith(".swift"))) {
    const text = readFileSync(file, "utf8");
    for (const match of text.matchAll(publicLiteral)) {
      inspectedLiterals += 1;
      const literal = match[1];
      if (containsPublicLegacy(literal)) {
        failures.push({
          code: "PUBLIC_LEGACY_SOURCE_COPY",
          path: relative(repoRoot, file),
        });
        classifications.PUBLIC_LEAK += 1;
      }
    }
  }

  return { inspectedLiterals };
}

function sourceAssetNames(repoRoot) {
  const assetRoot = path.join(repoRoot, assetsRelativePath);
  const assetDirectory = /\.(?:appiconset|colorset|dataset|imageset|symbolset)$/;
  const names = [];

  function visit(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const absolute = path.join(directory, entry.name);
      if (assetDirectory.test(entry.name)) {
        names.push(entry.name.replace(assetDirectory, ""));
      } else {
        visit(absolute);
      }
    }
  }

  visit(assetRoot);
  return names.sort();
}

// App icon sets present in the source catalog. Only the one selected by
// ASSETCATALOG_COMPILER_APPICON_NAME is emitted into the compiled catalog;
// any other appiconset is intentionally dropped by actool.
function sourceAppIconNames(repoRoot) {
  const assetRoot = path.join(repoRoot, assetsRelativePath);
  const nonIconLeaf = /\.(?:colorset|dataset|imageset|symbolset)$/;
  const names = [];

  function visit(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      if (/\.appiconset$/.test(entry.name)) {
        names.push(entry.name.replace(/\.appiconset$/, ""));
      } else if (!nonIconLeaf.test(entry.name)) {
        visit(path.join(directory, entry.name));
      }
    }
  }

  visit(assetRoot);
  return names.sort();
}

// The designated primary app icon recorded in the compiled Info.plist. This is
// the single appiconset actool compiles into the catalog; null when the bundle
// declares no primary icon name.
function designatedAppIconName(appPath) {
  const infoPath = path.join(appPath, "Info.plist");
  if (!existsSync(infoPath)) return null;
  const name = readPlist(infoPath)?.CFBundleIcons?.CFBundlePrimaryIcon?.CFBundleIconName;
  return typeof name === "string" && name.length > 0 ? name : null;
}

function readCompiledAssetNames(assetsCarPath) {
  try {
    const metadata = JSON.parse(run("xcrun", ["assetutil", "--info", assetsCarPath]));
    if (!Array.isArray(metadata)) throw new Error();
    return [...new Set(metadata
      .map((entry) => entry?.Name)
      .filter((name) => typeof name === "string" && name.length > 0))].sort();
  } catch {
    throw new Error("compiled asset metadata inspection failed");
  }
}

function inspectCompiledAssets({
  appPath,
  repoRoot,
  failures,
  compiledAssetNames,
}) {
  const assetsCarPath = path.join(appPath, "Assets.car");
  const present = existsSync(assetsCarPath) && lstatSync(assetsCarPath).size > 0;
  if (!present) {
    failures.push({ code: "MISSING_COMPILED_ASSET_CATALOG", path: "Assets.car" });
    return { present, expectedNames: sourceAssetNames(repoRoot), compiledNames: [] };
  }

  const expectedNames = sourceAssetNames(repoRoot);
  const compiledNames = compiledAssetNames ?? readCompiledAssetNames(assetsCarPath);
  const compiledSet = new Set(compiledNames);
  const appIconNames = new Set(sourceAppIconNames(repoRoot));
  const designatedAppIcon = designatedAppIconName(appPath);
  for (const name of expectedNames) {
    if (compiledSet.has(name)) continue;
    // A source appiconset that is not the designated primary icon is
    // deliberately excluded from the compiled catalog by actool, so its
    // absence is expected — not a missing-asset failure. When the bundle
    // declares no primary icon we keep the strict expectation.
    if (appIconNames.has(name) && designatedAppIcon !== null && name !== designatedAppIcon) {
      continue;
    }
    failures.push({ code: "MISSING_COMPILED_NAMED_ASSET", path: "Assets.car", name });
  }
  // The designated primary app icon must always be compiled. When it is also a
  // source asset the loop above already covers it; this guards the case where
  // the bundle names a primary icon absent from the source catalog.
  if (
    designatedAppIcon !== null
    && !compiledSet.has(designatedAppIcon)
    && !expectedNames.includes(designatedAppIcon)
  ) {
    failures.push({ code: "MISSING_COMPILED_NAMED_ASSET", path: "Assets.car", name: designatedAppIcon });
  }
  return { present, expectedNames, compiledNames };
}

function inspectCompiledResources({ appPath, catalog, failures, classifications }) {
  const lprojDirectories = readdirSync(appPath, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name.endsWith(".lproj"))
    .map((entry) => path.join(appPath, entry.name));
  const resourceFiles = lprojDirectories.flatMap((directory) =>
    filesRecursively(directory).filter((file) => /\.(?:strings|stringsdict)$/.test(file)),
  );
  let compiledKeyCount = 0;

  for (const language of requiredLanguages) {
    const file = path.join(appPath, `${language}.lproj`, "Localizable.strings");
    if (!existsSync(file)) {
      failures.push({ code: "MISSING_COMPILED_LOCALIZATION", language });
      continue;
    }
    const compiled = readPlist(file);
    compiledKeyCount += Object.keys(compiled).length;
    for (const [key, entry] of Object.entries(catalog.strings)) {
      const expected = entry?.localizations?.[language]?.stringUnit?.value;
      if (typeof expected !== "string") continue;
      if (compiled[key] !== expected) {
        failures.push({ code: "COMPILED_LOCALIZATION_MISMATCH", key, language });
      }
      if (typeof compiled[key] === "string" && containsPublicLegacy(compiled[key])) {
        failures.push({ code: "PUBLIC_LEGACY_COPY", path: relative(appPath, file), key, language });
        classifications.PUBLIC_LEAK += 1;
      }
    }
  }

  for (const file of resourceFiles) {
    const plist = readPlist(file);
    for (const [key, value] of Object.entries(plist)) {
      const serialized = typeof value === "string" ? value : JSON.stringify(value);
      if (containsPublicLegacy(serialized)) {
        failures.push({ code: "PUBLIC_LEGACY_COPY", path: relative(appPath, file), key });
        classifications.PUBLIC_LEAK += 1;
      }
    }
  }

  return {
    languageDirectories: lprojDirectories.map((directory) => path.basename(directory)).sort(),
    files: resourceFiles.map((file) => relative(appPath, file)).sort(),
    compiledKeyCount,
  };
}

function inspectInfoAndBinary({ appPath, expectedBundleIdentifier, failures, classifications }) {
  const infoPath = path.join(appPath, "Info.plist");
  if (!existsSync(infoPath)) throw new Error("compiled Info.plist is missing");
  const info = readPlist(infoPath);
  const sanitizedInfo = {
    bundleIdentifier: info.CFBundleIdentifier ?? null,
    displayName: info.CFBundleDisplayName ?? null,
    bundleName: info.CFBundleName ?? null,
    executable: info.CFBundleExecutable ?? null,
  };
  if (sanitizedInfo.bundleIdentifier !== expectedBundleIdentifier) {
    failures.push({ code: "UNEXPECTED_BUNDLE_IDENTIFIER", path: "Info.plist" });
  }
  for (const field of ["displayName", "bundleName"]) {
    const value = sanitizedInfo[field];
    if (typeof value === "string" && containsPublicLegacy(value)) {
      failures.push({ code: "PUBLIC_LEGACY_COPY", path: "Info.plist", field });
      classifications.PUBLIC_LEAK += 1;
    }
  }
  if (sanitizedInfo.displayName !== "Performe AI") {
    failures.push({ code: "MISSING_PUBLIC_PRODUCT_IDENTITY", path: "Info.plist" });
  }

  let binaryText = "";
  if (typeof sanitizedInfo.executable === "string") {
    const executablePath = path.join(appPath, sanitizedInfo.executable);
    if (existsSync(executablePath) && lstatSync(executablePath).isFile()) {
      try {
        binaryText = run("strings", ["-a", executablePath]);
      } catch {
        throw new Error("compiled executable scan failed");
      }
    }
  }
  for (const marker of debugFixtureMarkers) {
    if (binaryText.includes(marker)) {
      failures.push({ code: "DEBUG_FIXTURE_IN_RELEASE", path: sanitizedInfo.executable });
      classifications.DEBUG_ONLY += 1;
    }
  }
  classifications.ALLOWED_TECHNICAL += occurrences(
    `${sanitizedInfo.bundleIdentifier ?? ""}\n${sanitizedInfo.executable ?? ""}\n${binaryText}`,
    technicalLegacyPatterns,
  );
  return { info: sanitizedInfo, binaryCandidateCount: binaryText.length > 0 ? binaryText.split("\n").length : 0 };
}

export function scanSurface({
  appPath,
  baseline,
  repoRoot = defaultRepoRoot,
  compiledAssetNames,
  expectedBundleIdentifier = "com.bodyflow.app",
}) {
  if (!appPath || !existsSync(appPath) || !lstatSync(appPath).isDirectory()) {
    throw new Error("app path does not exist or is not a directory");
  }
  if (!baseline) throw new Error("baseline revision is required");
  if (typeof expectedBundleIdentifier !== "string" || expectedBundleIdentifier.length === 0) {
    throw new Error("expected bundle identifier is required");
  }

  const failures = [];
  const classifications = {
    ALLOWED_TECHNICAL: 0,
    PUBLIC_LEAK: 0,
    HISTORICAL_ASSET: 0,
    DEBUG_ONLY: 0,
    INTERNAL_CONTRACT: 0,
  };
  const source = inspectCatalog({ repoRoot, failures, classifications });
  const publicSource = inspectPublicSource({ repoRoot, failures, classifications });
  const assets = inspectAssets({ repoRoot, baseline, failures, classifications });
  const compiled = inspectCompiledResources({ appPath, catalog: source.catalog, failures, classifications });
  const binary = inspectInfoAndBinary({ appPath, expectedBundleIdentifier, failures, classifications });
  const compiledAssets = inspectCompiledAssets({
    appPath,
    repoRoot,
    failures,
    compiledAssetNames,
  });
  if (compiled.files.length === 0 && binary.binaryCandidateCount === 0 && !compiledAssets.present) {
    failures.push({ code: "EMPTY_COMPILED_SCAN", path: path.basename(appPath) });
  }

  return {
    schemaVersion: 1,
    status: failures.length === 0 ? "PASS" : "FAIL",
    brandAssetApprovalGate: assets.approvalGate,
    counts: {
      catalogKeys: source.keyCount,
      localizedValues: source.localizedValueCount,
      inspectedPublicSourceLiterals: publicSource.inspectedLiterals,
      compiledLocalizationKeys: compiled.compiledKeyCount,
      compiledResourceFiles: compiled.files.length,
      expectedNamedAssets: compiledAssets.expectedNames.length,
      compiledNamedAssets: compiledAssets.compiledNames.length,
      historicalAssetFiles: assets.historical.length,
      approvedNewAssetFiles: assets.approvedNewAssetFiles,
      binaryCandidates: binary.binaryCandidateCount,
      failures: failures.length,
    },
    classifications,
    compiled: {
      ...binary.info,
      expectedBundleIdentifier,
      localizationDirectories: compiled.languageDirectories,
      resourceFiles: compiled.files,
      assetCatalogPresent: compiledAssets.present,
      expectedAssetNames: compiledAssets.expectedNames,
      assetNames: compiledAssets.compiledNames,
    },
    historicalAssets: assets.historical,
    failures,
  };
}

function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!["--app", "--baseline", "--expected-bundle-id"].includes(flag) || !value) {
      throw new Error("usage: premium-surface-scan.mjs --app <path> --baseline <git-sha> [--expected-bundle-id <identifier>]");
    }
    values[flag.slice(2)] = value;
  }
  if (!values.app || !values.baseline) {
    throw new Error("usage: premium-surface-scan.mjs --app <path> --baseline <git-sha> [--expected-bundle-id <identifier>]");
  }
  return values;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try {
    const arguments_ = parseArguments(process.argv.slice(2));
    const result = scanSurface({
      appPath: path.resolve(arguments_.app),
      baseline: arguments_.baseline,
      expectedBundleIdentifier: arguments_["expected-bundle-id"],
    });
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    if (result.status !== "PASS") process.exitCode = 1;
  } catch (error) {
    process.stdout.write(`${JSON.stringify({
      schemaVersion: 1,
      status: "FAIL",
      failures: [{ code: "INPUT_OR_SCAN_ERROR", detail: error instanceof Error ? error.message : "unknown error" }],
    }, null, 2)}\n`);
    process.exitCode = 1;
  }
}
