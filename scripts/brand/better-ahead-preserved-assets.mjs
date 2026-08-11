import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const runFile = promisify(execFile);
const historicalCommit = "11f5a7cec331d4fc683b6cee5cdf046d3e89623d";
const historicalManifestPath = "design/brand/bodyflow-brand-assets.json";
const historicalManifestSha256 =
  "7f729f2221f95c6023fb98a01db4eae469c17568725eb96b6b5ead2ab2448b07";
const betterAheadManifestPath = "design/brand/better-ahead-brand-assets.json";
const catalogRoot =
  "apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets";
const appIconContentsPath = `${catalogRoot}/AppIcon.appiconset/Contents.json`;
const appIconContentsSha256 =
  "f1433e92cae162e6fa6bee2271a1c6dff34a7bc0bafeb2743033f3225d59e148";
const intentionalNewRoles = Object.freeze(["wordmark", "horizontal", "launch"]);
const requiredMasterRoles = Object.freeze(new Map([
  ["symbol", "symbol"],
  ["monochrome", "monochrome"],
  ["negative", "negative"],
]));
const requiredExportRoles = Object.freeze(new Set([
  "symbol",
  "monochrome",
  "negative",
  "app_icon",
]));

export async function betterAheadPreservedAssets(rootDirectory, options = {}) {
  const root = path.resolve(rootDirectory);
  const mismatches = [];
  const historicalManifest = {
    path: historicalManifestPath,
    baselineCommit: historicalCommit,
    expectedSha256: historicalManifestSha256,
    committedSha256: null,
    physicalSha256: null,
  };
  const result = {
    historicalManifest,
    historicalBrandVersion: null,
    historicalApprovalState: null,
    preserved: [],
    intentionalNewRoles: [],
    newAssets: [],
    mismatches,
  };

  const committedManifestBytes = await readCommittedFile(
    root,
    historicalCommit,
    historicalManifestPath,
    mismatches,
  );
  if (!committedManifestBytes) return result;
  historicalManifest.committedSha256 = sha256(committedManifestBytes);
  if (historicalManifest.committedSha256 !== historicalManifestSha256) {
    mismatches.push(
      `historical manifest committed sha256 mismatch: expected ${historicalManifestSha256}, received ${historicalManifest.committedSha256}`,
    );
    return result;
  }

  let committedManifest;
  try {
    committedManifest = JSON.parse(committedManifestBytes.toString("utf8"));
  } catch (error) {
    mismatches.push(`historical committed manifest is invalid JSON: ${errorMessage(error)}`);
    return result;
  }
  result.historicalBrandVersion = committedManifest.brand_version ?? null;
  result.historicalApprovalState = committedManifest.approval_state ?? null;
  if (result.historicalBrandVersion !== "1.0.0") {
    mismatches.push("historical committed manifest brand version must equal 1.0.0");
  }
  if (result.historicalApprovalState !== "approved") {
    mismatches.push("historical committed manifest approval state must equal approved");
  }

  const physicalManifestBytes = await readPhysicalFile(
    root,
    historicalManifestPath,
    "historical manifest",
    mismatches,
  );
  let physicalManifest;
  if (physicalManifestBytes) {
    historicalManifest.physicalSha256 = sha256(physicalManifestBytes);
    if (historicalManifest.physicalSha256 !== historicalManifestSha256) {
      mismatches.push(
        `historical manifest physical sha256 mismatch: expected ${historicalManifestSha256}, received ${historicalManifest.physicalSha256}`,
      );
    }
    try {
      physicalManifest = JSON.parse(physicalManifestBytes.toString("utf8"));
    } catch (error) {
      mismatches.push(`historical physical manifest is invalid JSON: ${errorMessage(error)}`);
    }
  }
  if (physicalManifest?.brand_version !== "1.0.0") {
    mismatches.push("historical physical manifest brand version must equal 1.0.0");
  }
  if (physicalManifest?.approval_state !== "approved") {
    mismatches.push("historical physical manifest approval state must equal approved");
  }

  const expectedPreserved = historicalPreservedEntries(committedManifest, mismatches);
  const declaration = await readBetterAheadManifest(root, mismatches);
  if (declaration) {
    validateDeclaration(declaration, expectedPreserved, mismatches);
    result.intentionalNewRoles = Array.isArray(declaration.intentional_new_roles)
      ? [...declaration.intentional_new_roles]
      : [];
    result.newAssets = Array.isArray(declaration.new_assets)
      ? [...declaration.new_assets]
      : [];
  }

  for (const expected of expectedPreserved) {
    const committedBytes = await readCommittedFile(
      root,
      historicalCommit,
      expected.historicalPath,
      mismatches,
    );
    const physicalBytes = await readPhysicalFile(
      root,
      expected.historicalPath,
      `preserved asset ${expected.historicalPath}`,
      mismatches,
    );
    const committedSha256 = committedBytes ? sha256(committedBytes) : null;
    const physicalSha256 = physicalBytes ? sha256(physicalBytes) : null;
    if (committedSha256 !== expected.historicalSha256) {
      mismatches.push(
        `preserved committed sha256 mismatch for ${expected.historicalPath}: expected ${expected.historicalSha256}, received ${committedSha256 ?? "missing"}`,
      );
    }
    if (physicalSha256 !== expected.historicalSha256) {
      mismatches.push(
        `preserved physical sha256 mismatch for ${expected.historicalPath}: expected ${expected.historicalSha256}, received ${physicalSha256 ?? "missing"}`,
      );
    }
    result.preserved.push({
      role: expected.role,
      historicalPath: expected.historicalPath,
      historicalSha256: expected.historicalSha256,
      committedSha256,
      physicalSha256,
      ...(expected.neutralCatalogPath
        ? { neutralCatalogPath: expected.neutralCatalogPath }
        : {}),
      classification: "preserved",
    });
  }

  if (options.requireCatalog === true && declaration) {
    if (validateCatalogIdentity(declaration, mismatches)) {
      await validateCatalog(root, result.preserved, result.newAssets, mismatches);
    }
  }
  return result;
}

function validateCatalogIdentity(manifest, mismatches) {
  let valid = true;
  if (manifest.approval_state !== "approved") {
    mismatches.push("catalog mode requires approval_state approved");
    valid = false;
  }
  if (manifest.brand_version !== "1.0.0") {
    mismatches.push("catalog mode requires brand_version 1.0.0");
    valid = false;
  }
  return valid;
}

function historicalPreservedEntries(manifest, mismatches) {
  const entries = [];
  if (isAsset(manifest.source)) {
    entries.push(preserved("approved_source", manifest.source.path, manifest.source.sha256));
  } else {
    mismatches.push("historical committed manifest source declaration is missing");
  }

  const masters = Array.isArray(manifest.masters) ? manifest.masters : [];
  for (const [id, role] of requiredMasterRoles) {
    const asset = masters.find((candidate) => candidate?.id === id);
    if (!isAsset(asset)) {
      mismatches.push(`historical committed manifest master is missing: ${id}`);
      continue;
    }
    entries.push(preserved(role, asset.path, asset.sha256));
  }

  const exports = Array.isArray(manifest.exports) ? manifest.exports : [];
  for (const asset of exports) {
    if (!isAsset(asset) || !requiredExportRoles.has(asset.role)) continue;
    entries.push(preserved(
      asset.role,
      asset.path,
      asset.sha256,
      neutralAlias(asset.path),
    ));
    if (asset.role === "app_icon") {
      const filename = path.posix.basename(asset.path);
      const catalogPath = `${catalogRoot}/AppIcon.appiconset/${filename}`;
      entries.push(preserved("app_icon", catalogPath, asset.sha256, catalogPath));
    }
  }
  return entries;
}

function neutralAlias(historicalPath) {
  const aliases = new Map([
    [
      "design/brand/exports/bodyflow-symbol.svg",
      `${catalogRoot}/BrandSymbol.imageset/brand-symbol.svg`,
    ],
    [
      "design/brand/exports/bodyflow-symbol-monochrome.svg",
      `${catalogRoot}/BrandMonochrome.imageset/brand-symbol-monochrome.svg`,
    ],
    [
      "design/brand/exports/bodyflow-symbol-negative.svg",
      `${catalogRoot}/BrandNegative.imageset/brand-symbol-negative.svg`,
    ],
  ]);
  return aliases.get(historicalPath);
}

function validateDeclaration(manifest, expectedPreserved, mismatches) {
  if (manifest.schema_version !== 1) {
    mismatches.push("Better Ahead manifest schema_version must equal 1");
  }
  if (manifest.product !== "Better Ahead") {
    mismatches.push("Better Ahead manifest product must equal Better Ahead");
  }
  if (typeof manifest.brand_version !== "string" || manifest.brand_version.length === 0) {
    mismatches.push("Better Ahead manifest brand_version must be non-empty");
  }
  if (!["candidate", "approved"].includes(manifest.approval_state)) {
    mismatches.push("Better Ahead manifest approval_state must be candidate or approved");
  }

  const historical = manifest.historical_manifest;
  if (!isPlainObject(historical)) {
    mismatches.push("Better Ahead historical manifest declaration is missing");
  } else {
    const required = {
      path: historicalManifestPath,
      sha256: historicalManifestSha256,
      brand_version: "1.0.0",
      approval_state: "approved",
    };
    for (const [field, expected] of Object.entries(required)) {
      if (historical[field] !== expected) {
        mismatches.push(
          `Better Ahead historical manifest ${field.replaceAll("_", " ")} mismatch: expected ${expected}, received ${historical[field] ?? "missing"}`,
        );
      }
    }
  }

  const declaredPreserved = Array.isArray(manifest.preserved) ? manifest.preserved : [];
  if (!Array.isArray(manifest.preserved)) {
    mismatches.push("Better Ahead preserved declaration must be an array");
  }
  const expectedByPath = new Map(
    expectedPreserved.map((asset) => [asset.historicalPath, asset]),
  );
  const seen = new Set();
  for (const asset of declaredPreserved) {
    if (!isPlainObject(asset)) {
      mismatches.push("Better Ahead preserved entry must be an object");
      continue;
    }
    const declaredPath = asset.historical_path;
    const pathError = relativePathError(declaredPath);
    if (pathError) {
      mismatches.push(`Better Ahead preserved historical path ${pathError}`);
      continue;
    }
    if (seen.has(declaredPath)) {
      mismatches.push(`duplicate Better Ahead preserved historical path: ${declaredPath}`);
      continue;
    }
    seen.add(declaredPath);
    const expected = expectedByPath.get(declaredPath);
    if (!expected) {
      mismatches.push(`unexpected Better Ahead preserved historical path: ${declaredPath}`);
      continue;
    }
    if (asset.role !== expected.role) {
      mismatches.push(`preserved role mismatch for ${declaredPath}`);
    }
    if (asset.historical_sha256 !== expected.historicalSha256) {
      mismatches.push(`preserved historical sha256 mismatch for ${declaredPath}`);
    }
    if ((asset.neutral_catalog_path ?? null) !== (expected.neutralCatalogPath ?? null)) {
      mismatches.push(`preserved neutral catalog path mismatch for ${declaredPath}`);
    }
    if (asset.neutral_catalog_path !== undefined) {
      const aliasError = relativePathError(asset.neutral_catalog_path);
      if (aliasError) {
        mismatches.push(`preserved neutral catalog path ${aliasError}`);
      }
      const imageSetName = path.posix.basename(path.posix.dirname(asset.neutral_catalog_path));
      if (/bodyflow|better-ahead/i.test(imageSetName)) {
        mismatches.push(`preserved neutral catalog path uses a product-specific set: ${asset.neutral_catalog_path}`);
      }
    }
  }
  for (const expectedPath of expectedByPath.keys()) {
    if (!seen.has(expectedPath)) {
      mismatches.push(`Better Ahead preserved declaration is missing: ${expectedPath}`);
    }
  }

  if (!Array.isArray(manifest.intentional_new_roles)
    || manifest.intentional_new_roles.toSorted().join("\0")
      !== intentionalNewRoles.toSorted().join("\0")) {
    mismatches.push("Better Ahead intentional new roles must be exactly horizontal, launch, wordmark");
  }
  if (!Array.isArray(manifest.new_assets)) {
    mismatches.push("Better Ahead new_assets declaration must be an array");
  }
}

async function validateCatalog(root, preservedAssets, newAssets, mismatches) {
  for (const asset of preservedAssets) {
    if (!asset.neutralCatalogPath) continue;
    const bytes = await readPhysicalFile(
      root,
      asset.neutralCatalogPath,
      `catalog asset ${asset.neutralCatalogPath}`,
      mismatches,
    );
    if (bytes && sha256(bytes) !== asset.historicalSha256) {
      mismatches.push(
        `catalog asset sha256 mismatch for ${asset.neutralCatalogPath}`,
      );
    }
    if (!asset.neutralCatalogPath.includes("/AppIcon.appiconset/")) {
      await validateImageSet(
        root,
        asset.neutralCatalogPath,
        ["monochrome", "negative"].includes(asset.role) ? "template" : "original",
        mismatches,
      );
    }
  }

  const newRoleCatalog = new Map([
    ["wordmark", `${catalogRoot}/BrandWordmark.imageset/better-ahead-wordmark.svg`],
    ["horizontal", `${catalogRoot}/BrandLogoHorizontal.imageset/better-ahead-horizontal.svg`],
    ["launch", `${catalogRoot}/BrandLaunch.imageset/better-ahead-launch.svg`],
  ]);
  for (const [role, expectedCatalogPath] of newRoleCatalog) {
    const matching = newAssets.filter((asset) => asset?.role === role);
    if (matching.length !== 1) {
      mismatches.push(`Better Ahead manifest must declare exactly one approved ${role} asset for catalog mode`);
      continue;
    }
    const asset = matching[0];
    const sourcePathError = relativePathError(asset.path);
    if (sourcePathError) {
      mismatches.push(`Better Ahead ${role} source path ${sourcePathError}`);
      continue;
    }
    if (!/^[0-9a-f]{64}$/u.test(asset.sha256)) {
      mismatches.push(`Better Ahead ${role} sha256 must be a complete lowercase SHA-256`);
      continue;
    }
    if (asset.neutral_catalog_path !== expectedCatalogPath) {
      mismatches.push(
        `Better Ahead ${role} neutral catalog path mismatch: expected ${expectedCatalogPath}, received ${asset.neutral_catalog_path ?? "missing"}`,
      );
      continue;
    }
    const sourceBytes = await readPhysicalFile(
      root,
      asset.path,
      `Better Ahead approved ${role} asset ${asset.path}`,
      mismatches,
    );
    if (sourceBytes && sha256(sourceBytes) !== asset.sha256) {
      mismatches.push(`Better Ahead approved ${role} sha256 mismatch for ${asset.path}`);
    }
    const catalogBytes = await readPhysicalFile(
      root,
      expectedCatalogPath,
      `catalog asset ${expectedCatalogPath}`,
      mismatches,
    );
    if (catalogBytes && sha256(catalogBytes) !== asset.sha256) {
      mismatches.push(`catalog asset sha256 mismatch for ${expectedCatalogPath}`);
    }
    await validateImageSet(root, expectedCatalogPath, "original", mismatches);
  }

  const contents = await readPhysicalFile(
    root,
    appIconContentsPath,
    `catalog asset ${appIconContentsPath}`,
    mismatches,
  );
  if (contents && sha256(contents) !== appIconContentsSha256) {
    mismatches.push(`catalog asset sha256 mismatch for ${appIconContentsPath}`);
  }
  const appIconDirectory = resolveRepositoryPath(root, path.posix.dirname(appIconContentsPath));
  try {
    const files = (await readdir(appIconDirectory)).toSorted();
    const expectedFiles = [
      "Contents.json",
      "bodyflow-app-icon-dark-1024.png",
      "bodyflow-app-icon-default-1024.png",
      "bodyflow-app-icon-tinted-1024.png",
    ].toSorted();
    if (files.join("\0") !== expectedFiles.join("\0")) {
      mismatches.push("AppIcon.appiconset contains missing, extra, or misnamed files");
    }
  } catch (error) {
    mismatches.push(`AppIcon.appiconset is unreadable: ${errorMessage(error)}`);
  }
}

async function validateImageSet(root, payloadPath, expectedIntent, mismatches) {
  const imageSetName = path.posix.basename(path.posix.dirname(payloadPath));
  const filename = path.posix.basename(payloadPath);
  const directoryPath = path.posix.dirname(payloadPath);
  const directory = resolveRepositoryPath(root, directoryPath);
  try {
    const files = (await readdir(directory)).toSorted();
    const expectedFiles = ["Contents.json", filename].toSorted();
    if (files.join("\0") !== expectedFiles.join("\0")) {
      mismatches.push(`${imageSetName} contains missing, extra, or misnamed files`);
    }
  } catch (error) {
    mismatches.push(`${imageSetName} is missing or unreadable: ${errorMessage(error)}`);
    return;
  }

  const contentsPath = `${directoryPath}/Contents.json`;
  const contentsBytes = await readPhysicalFile(
    root,
    contentsPath,
    `catalog asset ${contentsPath}`,
    mismatches,
  );
  if (!contentsBytes) return;
  try {
    const contents = JSON.parse(contentsBytes.toString("utf8"));
    if (JSON.stringify(contents.images) !== JSON.stringify([
      { filename, idiom: "universal" },
    ])) {
      mismatches.push(`${imageSetName} Contents.json has a missing or misnamed payload`);
    }
    if (contents.properties?.["preserves-vector-representation"] !== true
      || contents.properties?.["template-rendering-intent"] !== expectedIntent) {
      mismatches.push(`${imageSetName} Contents.json has invalid vector rendering properties`);
    }
  } catch (error) {
    mismatches.push(`${imageSetName} Contents.json is invalid JSON: ${errorMessage(error)}`);
  }
}

async function readBetterAheadManifest(root, mismatches) {
  const bytes = await readPhysicalFile(
    root,
    betterAheadManifestPath,
    "Better Ahead manifest",
    mismatches,
  );
  if (!bytes) return null;
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    mismatches.push(`Better Ahead manifest is invalid JSON: ${errorMessage(error)}`);
    return null;
  }
}

async function readCommittedFile(root, commit, relativePath, mismatches) {
  try {
    const { stdout } = await runFile(
      "git",
      ["show", `${commit}:${relativePath}`],
      { cwd: root, encoding: "buffer", maxBuffer: 64 * 1024 * 1024 },
    );
    return stdout;
  } catch (error) {
    mismatches.push(
      `committed baseline file is missing for ${relativePath}: ${errorMessage(error)}`,
    );
    return null;
  }
}

async function readPhysicalFile(root, relativePath, label, mismatches) {
  const pathError = relativePathError(relativePath);
  if (pathError) {
    mismatches.push(`${label} path ${pathError}`);
    return null;
  }
  const absolutePath = resolveRepositoryPath(root, relativePath);
  try {
    const metadata = await lstat(absolutePath);
    if (!metadata.isFile()) {
      mismatches.push(`${label} is not a regular file: ${relativePath}`);
      return null;
    }
    return await readFile(absolutePath);
  } catch (error) {
    mismatches.push(`${label} is missing or unreadable: ${relativePath}: ${errorMessage(error)}`);
    return null;
  }
}

function relativePathError(value) {
  if (typeof value !== "string" || value.length === 0) return "must be non-empty";
  if (path.posix.isAbsolute(value) || path.win32.isAbsolute(value)) {
    return "must be repository-relative; diagnostic paths are forbidden";
  }
  if (/[\0*?[\]{}]/u.test(value)) return "must not contain a wildcard";
  if (value.includes("\\")) return "must use POSIX separators";
  const normalized = path.posix.normalize(value);
  if (normalized !== value || value === "." || value.startsWith("../")) {
    return "must not contain root or traversal segments";
  }
  return null;
}

function resolveRepositoryPath(root, relativePath) {
  const absolutePath = path.resolve(root, relativePath);
  if (absolutePath !== root && !absolutePath.startsWith(`${root}${path.sep}`)) {
    throw new Error(`path escapes repository: ${relativePath}`);
  }
  return absolutePath;
}

function preserved(role, historicalPath, historicalSha256, neutralCatalogPath) {
  return {
    role,
    historicalPath,
    historicalSha256,
    ...(neutralCatalogPath ? { neutralCatalogPath } : {}),
  };
}

function isAsset(value) {
  return isPlainObject(value)
    && typeof value.path === "string"
    && /^[0-9a-f]{64}$/u.test(value.sha256);
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

export function historicalAssetMap(audit) {
  return {
    schemaVersion: 1,
    assets: audit.preserved
      .map(({ historicalPath: assetPath, historicalSha256 }) => ({
        path: assetPath,
        sha256: historicalSha256,
      }))
      .toSorted((left, right) => left.path.localeCompare(right.path, "en")),
  };
}

async function main() {
  const arguments_ = process.argv.slice(2);
  const allowed = new Set(["--check", "--emit-historical-map", "--require-catalog"]);
  const unknown = arguments_.filter((argument) => !allowed.has(argument));
  if (unknown.length > 0
    || (arguments_.includes("--check") && arguments_.includes("--emit-historical-map"))) {
    throw new Error("usage: better-ahead-preserved-assets.mjs --check [--require-catalog] | --emit-historical-map");
  }
  if (!arguments_.includes("--check") && !arguments_.includes("--emit-historical-map")) {
    throw new Error("one output mode is required");
  }
  const root = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "../..",
  );
  const audit = await betterAheadPreservedAssets(root, {
    requireCatalog: arguments_.includes("--require-catalog"),
  });
  if (audit.mismatches.length > 0) {
    process.stderr.write(`${audit.mismatches.join("\n")}\n`);
    process.exitCode = 1;
    return;
  }
  if (arguments_.includes("--emit-historical-map")) {
    process.stdout.write(`${JSON.stringify(historicalAssetMap(audit), null, 2)}\n`);
  } else {
    process.stdout.write(
      `Better Ahead preserved baseline verified (${audit.preserved.length} files)\n`,
    );
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => {
    process.stderr.write(`${errorMessage(error)}\n`);
    process.exitCode = 1;
  });
}
