import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { lstat, readFile, readdir, realpath } from "node:fs/promises";
import path from "node:path";
import { promisify, TextDecoder } from "node:util";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

import { canonicalBrandRenderer } from "./bodyflow-brand-renderer-contract.mjs";

const manifestRelativePath = "design/brand/bodyflow-brand-assets.json";
const exportsRelativePath = "design/brand/exports";
const runFile = promisify(execFile);
const approvedSource = Object.freeze({
  path: "design/brand/source/bodyflow-approved-board.jpg",
  sha256: "af44d4b2036638720eaaf58c05fa6098f69b21c7639b91bb4a60bc85c64c15b7",
  width: 1491,
  height: 1055,
  color_space: "sRGB",
});
const svgNamespace = "http://www.w3.org/2000/svg";
const allowedSvgElements = Object.freeze([
  "svg",
  "defs",
  "linearGradient",
  "stop",
  "g",
  "path",
]);
const allowedSvgAttributes = Object.freeze([
  "viewBox",
  "id",
  "x1",
  "y1",
  "x2",
  "y2",
  "offset",
  "stop-color",
  "transform",
  "fill",
  "stroke",
  "d",
]);
const allowedSvgPaintReferences = Object.freeze([
  "url(#upper-ribbon)",
  "url(#lower-ribbon)",
  "url(#arrow-ribbon)",
]);
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

  for (const [field, expected] of Object.entries(approvedSource)) {
    if (declaredSource[field] !== expected) {
      errors.push(
        `approved source contract mismatch: ${field}; expected ${expected}, received ${declaredSource[field]}`,
      );
    }
  }

  const sourcePath = resolveRepositoryPath(root, approvedSource.path);

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
  if (sha256 !== approvedSource.sha256) {
    errors.push(
      `approved source sha256 mismatch: expected ${approvedSource.sha256}, received ${sha256}`,
    );
  }

  try {
    const metadata = await sharp(source).metadata();
    result.source.dimensions = {
      width: metadata.width ?? null,
      height: metadata.height ?? null,
    };
    if (
      metadata.width !== approvedSource.width
      || metadata.height !== approvedSource.height
    ) {
      errors.push(
        `approved source dimensions mismatch: expected ${approvedSource.width}x${approvedSource.height}, received ${metadata.width}x${metadata.height}`,
      );
    }
    if (
      typeof metadata.space !== "string"
      || metadata.space.toLowerCase() !== approvedSource.color_space.toLowerCase()
    ) {
      errors.push(
        `approved source color space mismatch: expected ${approvedSource.color_space}, received ${metadata.space ?? "unknown"}`,
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
  const localErrors = [];
  let source;

  try {
    source = decodeCanonicalUtf8(contents);
  } catch (error) {
    localErrors.push(
      `${label} must use canonical UTF-8 bytes: ${errorMessage(error)}`,
    );
    errors.push(...localErrors);
    return;
  }

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

  const palettePaints = isPlainObject(palette)
    ? Object.values(palette).filter(isHexColor)
    : [];
  const allowedPaints = [
    ...palettePaints,
    "none",
    ...allowedSvgPaintReferences,
  ];
  let structure;
  if (/<!DOCTYPE\b|<!ENTITY\b/i.test(source)) {
    localErrors.push(`${label} contains a forbidden XML declaration`);
  } else {
    try {
      structure = await inspectSvgStructure(absolutePath, allowedPaints);
    } catch (error) {
      localErrors.push(`${label} is not valid XML: ${errorMessage(error)}`);
    }
  }

  if (structure) {
    if (structure.rootName !== "svg" || structure.rootNamespace !== svgNamespace) {
      localErrors.push(`${label} must contain an svg root in the canonical namespace`);
    }
    if (structure.viewBox !== asset.view_box) {
      localErrors.push(
        `${label} viewBox must equal manifest view_box ${asset.view_box ?? "unknown"}`,
      );
    }
    if (structure.fixedDimensionCount > 0) {
      localErrors.push(`${label} must not declare width or height`);
    }
    if (structure.prefixedElementCount > 0
      || structure.prefixedNamespaceCount > 0) {
      localErrors.push(`${label} contains a prefixed SVG namespace`);
    }
    if (structure.disallowedElementCount > 0) {
      localErrors.push(`${label} contains an element outside the SVG allowlist`);
    }
    if (structure.disallowedAttributeCount > 0) {
      localErrors.push(`${label} contains an attribute outside the SVG allowlist`);
    }
    if (structure.disallowedPaintCount > 0) {
      localErrors.push(`${label} contains paint outside the SVG allowlist`);
    }
    if (structure.pathCount === 0 || structure.invalidPathCount > 0) {
      localErrors.push(`${label} must contain outlined path geometry`);
    }
    if (structure.unpaintedPathCount > 0) {
      localErrors.push(`${label} contains path geometry without an allowlisted fill`);
    }
    if (structure.unpaintedStopCount > 0) {
      localErrors.push(`${label} contains a gradient stop without an allowlisted paint`);
    }
    if (structure.processingInstructionCount > 0) {
      localErrors.push(`${label} contains a forbidden XML processing instruction`);
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

  const allowedColors = new Set(
    palettePaints.map((color) => color.toUpperCase()),
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

async function inspectSvgStructure(absolutePath, allowedPaints) {
  const options = {
    encoding: "utf8",
    timeout: 5_000,
    maxBuffer: 256 * 1024,
  };
  await runFile("xmllint", ["--nonet", "--noout", absolutePath], options);

  const allowedElementPredicate = allowedSvgElements
    .map((name) => `local-name() = '${name}'`)
    .join(" or ");
  const allowedAttributePredicate = allowedSvgAttributes
    .map((name) => `local-name() = '${name}'`)
    .join(" or ");
  const allowedPaintPredicate = allowedPaints
    .map((paint) => `. = '${paint}'`)
    .join(" or ");
  const pathSelector =
    `//*[namespace-uri() = '${svgNamespace}' and local-name() = 'path']`;
  const stopSelector =
    `//*[namespace-uri() = '${svgNamespace}' and local-name() = 'stop']`;
  const countExpressions = [
    "count(/*/@width | /*/@height)",
    "count(//*[name() != local-name()])",
    "count(//namespace::*[name() != 'xml' and name() != ''])",
    `count(//*[not(namespace-uri() = '${svgNamespace}' and (${allowedElementPredicate}))])`,
    `count(//@*[not(namespace-uri() = '' and (${allowedAttributePredicate}))])`,
    `count((//@fill | //@stroke | //@stop-color)[not(${allowedPaintPredicate})])`,
    `count(${pathSelector})`,
    `count(${pathSelector}[not(@d) or normalize-space(@d) = ''])`,
    `count(${pathSelector}[not(@fill) and not(ancestor::*[@fill])])`,
    `count(${stopSelector}[not(@stop-color)])`,
    "count(//processing-instruction())",
  ];
  const countXPath = `concat(${countExpressions.join(", ' ', ")})`;
  const [rootName, rootNamespace, viewBox, countsOutput] = await Promise.all([
    runXmlXPath(absolutePath, "local-name(/*)", options),
    runXmlXPath(absolutePath, "namespace-uri(/*)", options),
    runXmlXPath(absolutePath, "string(/*/@viewBox)", options),
    runXmlXPath(absolutePath, countXPath, options),
  ]);
  const counts = countsOutput.split(" ").map(Number);
  if (counts.length !== countExpressions.length
    || counts.some((count) => !Number.isSafeInteger(count) || count < 0)) {
    throw new Error("xmllint returned an invalid structural count vector");
  }

  const [
    fixedDimensionCount,
    prefixedElementCount,
    prefixedNamespaceCount,
    disallowedElementCount,
    disallowedAttributeCount,
    disallowedPaintCount,
    pathCount,
    invalidPathCount,
    unpaintedPathCount,
    unpaintedStopCount,
    processingInstructionCount,
  ] = counts;
  return {
    rootName,
    rootNamespace,
    viewBox,
    fixedDimensionCount,
    prefixedElementCount,
    prefixedNamespaceCount,
    disallowedElementCount,
    disallowedAttributeCount,
    disallowedPaintCount,
    pathCount,
    invalidPathCount,
    unpaintedPathCount,
    unpaintedStopCount,
    processingInstructionCount,
  };
}

function decodeCanonicalUtf8(contents) {
  if (contents.length >= 3
    && contents[0] === 0xef
    && contents[1] === 0xbb
    && contents[2] === 0xbf) {
    throw new Error("UTF-8 byte-order marks are not permitted");
  }
  const source = new TextDecoder("utf-8", { fatal: true }).decode(contents);
  if (source.includes("\0") || !Buffer.from(source, "utf8").equals(contents)) {
    throw new Error("input is not a canonical UTF-8 encoding");
  }
  const declaration = source.match(/^\s*<\?xml\b([\s\S]*?)\?>/i);
  const declaredEncoding = declaration?.[1].match(
    /\bencoding\s*=\s*["']([^"']+)["']/i,
  )?.[1];
  if (declaredEncoding !== undefined && declaredEncoding.toUpperCase() !== "UTF-8") {
    throw new Error(`XML encoding declaration is ${declaredEncoding}, not UTF-8`);
  }
  return source;
}

async function runXmlXPath(absolutePath, expression, options) {
  const { stdout } = await runFile(
    "xmllint",
    ["--nonet", "--xpath", expression, absolutePath],
    options,
  );
  return stdout.trim();
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
