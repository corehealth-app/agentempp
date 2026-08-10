import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { lstat, readFile, readdir, realpath } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

import { canonicalBrandRenderer } from "./bodyflow-brand-renderer-contract.mjs";

const manifestRelativePath = "design/brand/bodyflow-brand-assets.json";
const exportsRelativePath = "design/brand/exports";
const runFile = promisify(execFile);
const requiredMasterIds = [
  "symbol",
  "wordmark",
  "horizontal",
  "monochrome",
  "negative",
];
const approvedExportHashes = new Map([
  ["symbol-vector", "01343fcb7aa4a52b303bb9a602180f13973c74d2b53704eaa817ce1b9a9f5eb9"],
  ["symbol-png-44", "d1fd4fb65559fd794b1a825a2da48e354011a4bb1551b87c42fccbe749cd7725"],
  ["symbol-png-88", "6221f43bf532380524cba828aabe50a75d88c3b658b346250f291c70b87e5f97"],
  ["symbol-png-132", "89eee28f8c122ac7188995a80fc46a8f04578e03f68548f7c568406d04fd29c0"],
  ["symbol-png-512", "d272fc80e6d0592e67aac29bb752fcd9f516024a6c9793bb18225130a93c3412"],
  ["symbol-png-1024", "c1b3211e35b5e14345f90ed40ce26fadaec241bcf8ab621a0ddf0245749088e3"],
  ["wordmark-vector", "57503318200bf68e5e76665675b6a8a7bf743f8ceb754e9599ec9754a9bf163d"],
  ["wordmark-png-320", "f30910270bbd82cc78359ee4b6bf857c8f69f48773a15555f1b540da007f754b"],
  ["wordmark-png-640", "b324e888da5998fa7aa03b2cf1230ff5e7bda875ab53b2c314424c49cbd6e2e0"],
  ["wordmark-png-960", "71690737047267eb3ac8891206538bb3e40f4cf41bd698fa1de909ec881fd5bc"],
  ["horizontal-vector", "cb88d3af9c6687573f06c34349c9c8bda2e602f8862cc728ca564ed880708cb0"],
  ["horizontal-png-360", "36c11814729657d6c7194b23e9dcb7fc050c6c263f304fd489587ff802ed27d5"],
  ["horizontal-png-720", "4510f7b318841b4a5f9760dc84e724b18dda7f17bd0b81ac22cccb6e790ccb8a"],
  ["horizontal-png-1080", "8019c4b6305d5a3468987ef27ae05ec914848fe4e1e1509db237a6547a45f105"],
  ["monochrome-vector", "6809439b3b5de85682665d65c26c9088159420eab55b92606878776501d6ce36"],
  ["monochrome-png-44", "6677b8ae8b3a4fe152e48cf6b0e0999121d04e7dc1d9ff8a69213f82a0ab3807"],
  ["monochrome-png-88", "8ef78c14517bc118282de9848e7572b0ec405136ead1fcda1a9cacbf3b2534a9"],
  ["monochrome-png-132", "0c7ab08351e7d21e6a43f67591c4f2bf040f9a0a9dc030172bad06f4e0776f94"],
  ["negative-vector", "a8f1ff09714181cb64d66c3bdf8481ec298d425adca514636c4ffd9d3eeb9647"],
  ["negative-png-44", "27954fd7666e1ba108a7f47e0f351df6c0136c0ef310b32bcc0cfaaba6d657da"],
  ["negative-png-88", "a69f656631e3d88fb3e3a2f966a1c1848c92d02924a8364d08a15c1b4a05de8b"],
  ["negative-png-132", "d99817a75434d5ceb752f86a5ac79b0a792d070603be655fc5ddf3ba22167729"],
  ["launch-vector", "06580ac994f24363ae04f767c0c9068043cae1a2d6af5946361b8e9ac2095e38"],
  ["app-icon-default", "400f0b86753226cc26e682b073689311d4086a50594b0f61e1b114d901d2dab8"],
  ["app-icon-dark", "361e42e33a442a961a34d38b61847d88287424d210c17721068fae0c4b10c2fc"],
  ["app-icon-tinted", "10c3e7af9f15e4209c79002df05495d9709c3b1c4577ce1f94c129899cc04703"],
  ["review-comparison", "822011b4478e1af322ab83c0be24d8d1a4fbbe27a57a03279cf7300822be64f4"],
  ["review-reduced-sizes", "263b48460df5b12fd800ccaad55768d2a17c691b397f371ba67c80e0cf67f1e1"],
  ["review-light-dark", "cfca072081070b3cb94ceea8a6105c57d80bb64dceb45143e3dc740750c2d5c8"],
]);

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
  validateRendererContract(manifest.renderer, errors);
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
  validateMasterFamily(masters, manifest.palette, errors);
  await validateAssets({
    root,
    rootRealPath,
    assets: [...masters, ...exports],
    masters,
    palette: manifest.palette,
    exports,
    errors,
  });

  return result;
}

function validateRendererContract(renderer, errors) {
  if (!isPlainObject(renderer)) {
    errors.push("manifest renderer must be an object");
    return;
  }

  compareRendererContract(errors, canonicalBrandRenderer, renderer);
}

function compareRendererContract(errors, expected, received, prefix = "") {
  for (const [key, expectedValue] of Object.entries(expected)) {
    const field = prefix ? `${prefix}.${key}` : key;
    const receivedValue = received[key];
    if (isPlainObject(expectedValue)) {
      if (isPlainObject(receivedValue)) {
        compareRendererContract(errors, expectedValue, receivedValue, field);
      } else {
        errors.push(
          `renderer contract mismatch: ${field}; expected object, received ${receivedValue}`,
        );
      }
    } else if (receivedValue !== expectedValue) {
      errors.push(
        `renderer contract mismatch: ${field}; expected ${expectedValue}, received ${receivedValue}`,
      );
    }
  }

  for (const key of Object.keys(received)) {
    if (Object.hasOwn(expected, key)) continue;
    const field = prefix ? `${prefix}.${key}` : key;
    errors.push(`renderer contract mismatch: ${field}; unexpected field`);
  }
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

function validateMasterFamily(masters, palette, errors) {
  const declaredIds = masters
    .filter((asset) => isPlainObject(asset) && isNonEmptyString(asset.id))
    .map((asset) => asset.id);

  if (declaredIds.join("|") !== requiredMasterIds.join("|")) {
    errors.push(
      `manifest masters must declare exactly: ${requiredMasterIds.join(", ")}`,
    );
  }

  if (!isPlainObject(palette) || Object.keys(palette).length === 0) {
    errors.push("manifest palette must be a non-empty object");
    return;
  }

  for (const [name, color] of Object.entries(palette)) {
    if (!isNonEmptyString(name) || !isHexColor(color)) {
      errors.push(`manifest palette color is invalid: ${name}`);
    }
  }
}

async function validateAssets({
  root,
  rootRealPath,
  assets,
  masters,
  palette,
  exports,
  errors,
}) {
  const ids = new Set();
  const paths = new Set();
  const masterPaths = new Set(
    masters
      .filter((asset) => isPlainObject(asset) && isNonEmptyString(asset.path))
      .map((asset) => toPosixPath(asset.path)),
  );

  for (const asset of exports) {
    if (!isPlainObject(asset) || !isNonEmptyString(asset.id)) continue;
    const approvedHash = approvedExportHashes.get(asset.id);
    if (approvedHash === undefined) {
      errors.push("approved export baseline is missing: " + asset.id);
    } else if (asset.sha256 !== approvedHash) {
      errors.push("approved export sha256 mismatch: " + asset.id);
    }
  }
  const declaredExportIds = new Set(
    exports
      .filter((asset) => isPlainObject(asset) && isNonEmptyString(asset.id))
      .map((asset) => asset.id),
  );
  for (const approvedId of approvedExportHashes.keys()) {
    if (!declaredExportIds.has(approvedId)) {
      errors.push(`approved export is missing: ${approvedId}`);
    }
  }

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

    if (masterPaths.has(normalizedPath)) {
      await validateSvgMaster({
        asset,
        absolutePath,
        contents,
        palette,
        errors,
      });
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

async function validateSvgMaster({
  asset,
  absolutePath,
  contents,
  palette,
  errors,
}) {
  const label = `SVG master ${asset.id ?? "unknown"}`;
  const source = contents.toString("utf8");
  const localErrors = [];

  if (!toPosixPath(asset.path).startsWith("design/brand/masters/")
    || path.extname(asset.path).toLowerCase() !== ".svg") {
    localErrors.push(`${label} must be an SVG below design/brand/masters`);
  }
  if (!isNonEmptyString(asset.view_box)) {
    localErrors.push(`${label} must declare view_box metadata`);
  }
  if (!isNonEmptyString(asset.role)) {
    localErrors.push(`${label} must declare a semantic role`);
  }
  if (asset.contains_text !== false) {
    localErrors.push(`${label} contains_text must be false`);
  }

  try {
    await runFile("xmllint", ["--noout", absolutePath], {
      timeout: 5_000,
      maxBuffer: 256 * 1024,
    });
  } catch (error) {
    localErrors.push(`${label} is not valid XML: ${errorMessage(error)}`);
  }

  const rootMatch = source.match(/<svg\b([^>]*)>/i);
  if (!rootMatch) {
    localErrors.push(`${label} must contain an svg root element`);
  } else {
    const attributes = rootMatch[1];
    const viewBox = attributeValue(attributes, "viewBox");
    if (!viewBox || viewBox !== asset.view_box) {
      localErrors.push(
        `${label} viewBox must equal manifest view_box ${asset.view_box ?? "unknown"}`,
      );
    }
    if (hasAttribute(attributes, "width") || hasAttribute(attributes, "height")) {
      localErrors.push(`${label} must not declare width or height`);
    }
  }

  for (const tag of ["text", "image", "script", "foreignObject", "style"]) {
    if (new RegExp(`<${tag}\\b`, "i").test(source)) {
      localErrors.push(`${label} contains forbidden SVG element <${tag}>`);
    }
  }
  if (/\bfont(?:-family|-face)?\s*=|\bfont-family\s*:|<font\b/i.test(source)) {
    localErrors.push(`${label} contains a live font declaration`);
  }
  if (/\sstyle\s*=|@import\b/i.test(source)) {
    localErrors.push(`${label} contains an imported or inline style declaration`);
  }
  if (/\b(?:href|xlink:href)\s*=\s*["'](?!#)/i.test(source)) {
    localErrors.push(`${label} contains an external SVG reference`);
  }
  if (/url\(\s*["']?(?!#)/i.test(source)) {
    localErrors.push(`${label} contains a non-local paint reference`);
  }

  const paths = [...source.matchAll(/<path\b[^>]*\bd\s*=\s*["']([^"']+)["'][^>]*>/gi)];
  if (paths.length === 0 || paths.every((match) => match[1].trim().length === 0)) {
    localErrors.push(`${label} must contain outlined path geometry`);
  }

  const allowedColors = new Set(
    isPlainObject(palette)
      ? Object.values(palette).filter(isHexColor).map((color) => color.toUpperCase())
      : [],
  );
  for (const match of source.matchAll(/#[0-9a-f]{3,8}\b/gi)) {
    const color = match[0].toUpperCase();
    if (!allowedColors.has(color)) {
      localErrors.push(`${label} color is not declared in manifest palette: ${color}`);
    }
  }

  if (localErrors.length === 0) {
    try {
      const { data, info } = await sharp(contents, { density: 144 })
        .resize(256, 256, { fit: "contain" })
        .ensureAlpha()
        .raw()
        .toBuffer({ resolveWithObject: true });
      let hasVisiblePixel = false;
      for (let offset = info.channels - 1; offset < data.length; offset += info.channels) {
        if (data[offset] > 0) {
          hasVisiblePixel = true;
          break;
        }
      }
      if (!hasVisiblePixel) {
        localErrors.push(`${label} has empty visible bounds`);
      }
    } catch (error) {
      localErrors.push(`${label} could not be rendered: ${errorMessage(error)}`);
    }
  }

  errors.push(...localErrors);
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

function isHexColor(value) {
  return typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value);
}

function hasAttribute(attributes, name) {
  return new RegExp(`(?:^|\\s)${name}\\s*=`, "i").test(attributes);
}

function attributeValue(attributes, name) {
  const match = attributes.match(
    new RegExp(`(?:^|\\s)${name}\\s*=\\s*["']([^"']+)["']`, "i"),
  );
  return match?.[1] ?? null;
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
