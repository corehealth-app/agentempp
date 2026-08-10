import { createHash } from "node:crypto";
import { lstat, readFile, readdir, realpath } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

const manifestRelativePath = "design/brand/bodyflow-brand-assets.json";
const exportsRelativePath = "design/brand/exports";

export async function validateBrandContract(rootDirectory) {
  const errors = [];
  const root = path.resolve(rootDirectory);
  const rootRealPath = await realpath(root);
  const result = {
    schemaVersion: null,
    source: {
      sha256: null,
      dimensions: { width: null, height: null },
    },
    errors,
  };

  const manifestPath = resolveRepositoryPath(root, manifestRelativePath);
  let manifest;

  try {
    manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  } catch (error) {
    errors.push(`manifest is unreadable: ${errorMessage(error)}`);
    return result;
  }

  result.schemaVersion = manifest.schema_version ?? null;
  if (manifest.schema_version !== 1) {
    errors.push("manifest schema_version must equal 1");
  }
  if (!isNonEmptyString(manifest.brand_version)) {
    errors.push("manifest brand_version must be a non-empty string");
  }
  if (!["candidate", "approved"].includes(manifest.approval_state)) {
    errors.push("manifest approval_state must be candidate or approved");
  }
  if (!Array.isArray(manifest.masters)) {
    errors.push("manifest masters must be an array");
  }
  if (!Array.isArray(manifest.exports)) {
    errors.push("manifest exports must be an array");
  }

  await validateSource({
    root,
    rootRealPath,
    declaredSource: manifest.source,
    result,
    errors,
  });

  const masters = Array.isArray(manifest.masters) ? manifest.masters : [];
  const exports = Array.isArray(manifest.exports) ? manifest.exports : [];
  await validateAssets({
    root,
    rootRealPath,
    assets: [...masters, ...exports],
    exports,
    errors,
  });

  return result;
}

async function validateSource({
  root,
  rootRealPath,
  declaredSource,
  result,
  errors,
}) {
  if (!isPlainObject(declaredSource)) {
    errors.push("manifest source must be an object");
    return;
  }

  const sourcePath = resolveRepositoryPathOrError(
    root,
    declaredSource.path,
    "source",
    errors,
  );
  if (!sourcePath) {
    return;
  }

  const source = await readRepositoryFile({
    rootRealPath,
    absolutePath: sourcePath,
    label: "source",
    errors,
  });
  if (!source) {
    return;
  }

  const sha256 = hashBuffer(source);
  result.source.sha256 = sha256;
  if (sha256 !== declaredSource.sha256) {
    errors.push(
      `source sha256 mismatch: expected ${declaredSource.sha256}, received ${sha256}`,
    );
  }

  try {
    const metadata = await sharp(source).metadata();
    result.source.dimensions = {
      width: metadata.width ?? null,
      height: metadata.height ?? null,
    };
    if (
      metadata.width !== declaredSource.width
      || metadata.height !== declaredSource.height
    ) {
      errors.push(
        `source dimensions mismatch: expected ${declaredSource.width}x${declaredSource.height}, received ${metadata.width}x${metadata.height}`,
      );
    }
    if (
      typeof metadata.space !== "string"
      || metadata.space.toLowerCase() !== String(declaredSource.color_space).toLowerCase()
    ) {
      errors.push(
        `source color space mismatch: expected ${declaredSource.color_space}, received ${metadata.space ?? "unknown"}`,
      );
    }
  } catch (error) {
    errors.push(`source raster metadata is unreadable: ${errorMessage(error)}`);
  }
}

async function validateAssets({ root, rootRealPath, assets, exports, errors }) {
  const ids = new Set();
  const paths = new Set();

  for (const asset of assets) {
    if (!isPlainObject(asset)) {
      errors.push("declared asset must be an object");
      continue;
    }

    if (!isNonEmptyString(asset.id)) {
      errors.push("declared asset id must be a non-empty string");
    } else if (ids.has(asset.id)) {
      errors.push(`duplicate asset id: ${asset.id}`);
    } else {
      ids.add(asset.id);
    }

    if (!isNonEmptyString(asset.path)) {
      errors.push(`declared asset path is invalid for ${asset.id ?? "unknown"}`);
      continue;
    }
    const normalizedPath = toPosixPath(asset.path);
    if (paths.has(normalizedPath)) {
      errors.push(`duplicate asset path: ${normalizedPath}`);
    } else {
      paths.add(normalizedPath);
    }

    const absolutePath = resolveRepositoryPathOrError(
      root,
      asset.path,
      `asset ${asset.id ?? "unknown"}`,
      errors,
    );
    if (!absolutePath) {
      continue;
    }

    const contents = await readRepositoryFile({
      rootRealPath,
      absolutePath,
      label: `declared asset ${asset.id ?? "unknown"}`,
      errors,
      missingMessage: `declared asset is missing: ${normalizedPath}`,
    });
    if (!contents) {
      continue;
    }
    if (!isSha256(asset.sha256)) {
      errors.push(`declared asset sha256 is invalid: ${asset.id ?? "unknown"}`);
    } else {
      const actualHash = hashBuffer(contents);
      if (actualHash !== asset.sha256) {
        errors.push(`declared asset sha256 mismatch: ${normalizedPath}`);
      }
    }
  }

  const declaredExports = new Set(
    exports
      .filter((asset) => isPlainObject(asset) && isNonEmptyString(asset.path))
      .map((asset) => toPosixPath(asset.path)),
  );
  const diskExports = await listRepositoryFiles(
    root,
    rootRealPath,
    exportsRelativePath,
    errors,
  );

  for (const diskExport of diskExports) {
    if (!declaredExports.has(diskExport)) {
      errors.push(`undeclared export: ${diskExport}`);
    }
  }
}

async function readRepositoryFile({
  rootRealPath,
  absolutePath,
  label,
  errors,
  missingMessage = `${label} is missing`,
}) {
  try {
    const metadata = await lstat(absolutePath);
    if (metadata.isSymbolicLink() || !metadata.isFile()) {
      errors.push(`${label} must be a regular file`);
      return null;
    }
    const fileRealPath = await realpath(absolutePath);
    if (!isInside(rootRealPath, fileRealPath)) {
      errors.push(`${label} path escapes repository`);
      return null;
    }
    return await readFile(fileRealPath);
  } catch (error) {
    if (error?.code === "ENOENT") {
      errors.push(missingMessage);
    } else {
      errors.push(`${label} is unreadable: ${errorMessage(error)}`);
    }
    return null;
  }
}

async function listRepositoryFiles(
  root,
  rootRealPath,
  relativeDirectory,
  errors,
) {
  const absoluteDirectory = resolveRepositoryPath(root, relativeDirectory);
  try {
    const directoryRealPath = await realpath(absoluteDirectory);
    if (!isInside(rootRealPath, directoryRealPath)) {
      errors.push(`${relativeDirectory} path escapes repository`);
      return [];
    }
    return await walkDirectory(root, directoryRealPath, errors);
  } catch (error) {
    if (error?.code === "ENOENT") {
      return [];
    }
    errors.push(`${relativeDirectory} is unreadable: ${errorMessage(error)}`);
    return [];
  }
}

async function walkDirectory(root, directory, errors) {
  const files = [];
  const entries = await readdir(directory, { withFileTypes: true });

  for (const entry of entries) {
    const absolutePath = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) {
      errors.push(`export must not be a symbolic link: ${relativePath(root, absolutePath)}`);
    } else if (entry.isDirectory()) {
      files.push(...await walkDirectory(root, absolutePath, errors));
    } else if (entry.isFile()) {
      files.push(relativePath(root, absolutePath));
    } else {
      errors.push(`export must be a regular file: ${relativePath(root, absolutePath)}`);
    }
  }

  return files.sort();
}

function resolveRepositoryPathOrError(root, declaredPath, label, errors) {
  if (!isNonEmptyString(declaredPath)) {
    errors.push(`${label} path is invalid`);
    return null;
  }
  const absolutePath = resolveRepositoryPath(root, declaredPath);
  if (!isInside(root, absolutePath)) {
    errors.push(`${label} path escapes repository: ${declaredPath}`);
    return null;
  }
  return absolutePath;
}

function resolveRepositoryPath(root, declaredPath) {
  return path.resolve(root, declaredPath);
}

function isInside(root, candidate) {
  const difference = path.relative(root, candidate);
  return difference === "" || (!difference.startsWith("..") && !path.isAbsolute(difference));
}

function relativePath(root, absolutePath) {
  return toPosixPath(path.relative(root, absolutePath));
}

function toPosixPath(value) {
  return value.replaceAll(path.sep, "/");
}

function hashBuffer(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.length > 0;
}

function isSha256(value) {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

async function runCheck() {
  const repositoryRoot = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "../..",
  );
  const result = await validateBrandContract(repositoryRoot);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (result.errors.length > 0) {
    process.exitCode = 1;
  }
}

if (path.resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url)) {
  await runCheck();
}
