import { createHash } from "node:crypto";
import {
  access,
  mkdir,
  readFile,
  rename,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

import { assertCanonicalBrandRenderer } from "./bodyflow-brand-renderer-contract.mjs";

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultRepositoryRoot = path.resolve(moduleDirectory, "../..");
const manifestRelativePath = "design/brand/bodyflow-brand-assets.json";
const catalogRelativePath =
  "apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets";
const requiredMasterIds = [
  "symbol",
  "wordmark",
  "horizontal",
  "monochrome",
  "negative",
];

const vectorJobs = [
  vectorJob("symbol-vector", "bodyflow-symbol.svg", "symbol", "symbol"),
  vectorJob("wordmark-vector", "bodyflow-wordmark.svg", "wordmark", "wordmark"),
  vectorJob(
    "horizontal-vector",
    "bodyflow-horizontal.svg",
    "horizontal",
    "horizontal",
  ),
  vectorJob(
    "monochrome-vector",
    "bodyflow-symbol-monochrome.svg",
    "monochrome",
    "monochrome",
  ),
  vectorJob(
    "negative-vector",
    "bodyflow-symbol-negative.svg",
    "negative",
    "negative",
  ),
];

const rasterJobs = [
  ...squareRasterJobs("symbol", "symbol", [44, 88, 132, 512, 1024]),
  ...widthRasterJobs("wordmark", "wordmark", [320, 640, 960], 960, 256),
  ...widthRasterJobs(
    "horizontal",
    "horizontal",
    [360, 720, 1080],
    1536,
    512,
  ),
  ...squareRasterJobs("monochrome", "monochrome", [44, 88, 132]),
  ...squareRasterJobs("negative", "negative", [44, 88, 132]),
];

const launchAsset = {
  id: "launch-vector",
  path: "design/brand/exports/bodyflow-launch.svg",
  media_type: "image/svg+xml",
  role: "launch",
  alpha: "vector",
  color_space: "sRGB",
};

const appIconJobs = [
  appIconJob("app-icon-default", "bodyflow-app-icon-default-1024.png", "default"),
  appIconJob("app-icon-dark", "bodyflow-app-icon-dark-1024.png", "dark"),
  appIconJob("app-icon-tinted", "bodyflow-app-icon-tinted-1024.png", "tinted"),
];

export const productExportAssets = [
  ...assetsForRole("symbol"),
  ...assetsForRole("wordmark"),
  ...assetsForRole("horizontal"),
  ...assetsForRole("monochrome"),
  ...assetsForRole("negative"),
  launchAsset,
  ...appIconJobs.map(({ asset }) => asset),
];

export const reviewExportAssets = [
  reviewAsset("review-comparison", "brand-comparison.png"),
  reviewAsset("review-reduced-sizes", "brand-reduced-sizes.png"),
  reviewAsset("review-light-dark", "brand-light-dark.png"),
];

function assetsForRole(role) {
  return [
    ...vectorJobs
      .filter(({ asset }) => asset.role === role)
      .map(({ asset }) => asset),
    ...rasterJobs
      .filter(({ asset }) => asset.role === role)
      .map(({ asset }) => asset),
  ];
}

export async function renderBodyFlowBrandAssets(
  repositoryRoot = defaultRepositoryRoot,
) {
  assertCanonicalBrandRenderer();
  const root = path.resolve(repositoryRoot);
  const manifestPath = path.join(root, manifestRelativePath);
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const masters = await loadAndVerifyInputs(root, manifest);

  for (const job of vectorJobs) {
    await atomicWrite(
      path.join(root, job.asset.path),
      masters.get(job.masterId).contents,
    );
  }

  for (const job of rasterJobs) {
    const output = await renderTransparentPng(
      masters.get(job.masterId).contents,
      job.asset.width,
      job.asset.height,
    );
    await atomicWrite(path.join(root, job.asset.path), output);
  }

  const launchSvg = createLaunchSvg(masters.get("horizontal").contents);
  await atomicWrite(path.join(root, launchAsset.path), launchSvg);

  for (const job of appIconJobs) {
    const output = await renderAppIcon(job.variant, masters);
    await atomicWrite(path.join(root, job.asset.path), output);
  }

  await populateAssetCatalog(root, masters, launchSvg);

  const availableReviews = [];
  for (const asset of reviewExportAssets) {
    if (await fileExists(path.join(root, asset.path))) {
      availableReviews.push(asset);
    }
  }
  await writeManifestExports(root, manifest, [
    ...productExportAssets,
    ...availableReviews,
  ]);

  return { productCount: productExportAssets.length };
}

export async function writeManifestExports(root, manifest, assets) {
  const exports = [];
  for (const asset of assets) {
    const contents = await readFile(path.join(root, asset.path));
    exports.push({ ...asset, sha256: sha256(contents) });
  }
  const nextManifest = { ...manifest, exports };
  await atomicWrite(
    path.join(root, manifestRelativePath),
    `${JSON.stringify(nextManifest, null, 2)}\n`,
  );
  return nextManifest;
}

export async function atomicWrite(destination, contents) {
  await mkdir(path.dirname(destination), { recursive: true });
  const temporary = path.join(
    path.dirname(destination),
    `.${path.basename(destination)}.${process.pid}.tmp`,
  );
  await writeFile(temporary, contents);
  await rename(temporary, destination);
}

async function loadAndVerifyInputs(root, manifest) {
  const source = await readFile(path.join(root, manifest.source.path));
  if (sha256(source) !== manifest.source.sha256) {
    throw new Error("refusing to render from a mutated approved source");
  }
  if (
    !Array.isArray(manifest.masters)
    || manifest.masters.map((asset) => asset.id).join("|")
      !== requiredMasterIds.join("|")
  ) {
    throw new Error("refusing to render an incomplete master family");
  }

  const masters = new Map();
  for (const asset of manifest.masters) {
    const contents = await readFile(path.join(root, asset.path));
    if (sha256(contents) !== asset.sha256) {
      throw new Error(`refusing dirty master hash: ${asset.id}`);
    }
    masters.set(asset.id, { ...asset, contents });
  }
  return masters;
}

async function renderTransparentPng(svg, width, height) {
  return sharp(svg, { density: 288 })
    .resize(width, height, {
      fit: "contain",
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .ensureAlpha()
    .toColourspace("srgb")
    .png({ compressionLevel: 9, adaptiveFiltering: false, palette: false })
    .toBuffer();
}

async function renderAppIcon(variant, masters) {
  const source = variant === "tinted"
    ? masters.get("monochrome").contents
    : masters.get("symbol").contents;
  const background = {
    default: "#006C6A",
    dark: "#142C33",
    tinted: "#F7F1E7",
  }[variant];
  const mark = await sharp(source, { density: 288 })
    .resize(704, 704, { fit: "contain" })
    .ensureAlpha()
    .png({ compressionLevel: 9, adaptiveFiltering: false })
    .toBuffer();

  return sharp({
    create: {
      width: 1024,
      height: 1024,
      channels: 3,
      background,
    },
  })
    .composite([{ input: mark, left: 160, top: 160 }])
    .flatten({ background })
    .removeAlpha()
    .toColourspace("srgb")
    .png({ compressionLevel: 9, adaptiveFiltering: false, palette: false })
    .toBuffer();
}

function createLaunchSvg(horizontalSvg) {
  const source = horizontalSvg.toString("utf8");
  const body = source.match(/<svg\b[^>]*>([\s\S]*)<\/svg>\s*$/i)?.[1];
  if (!body || /<text\b/i.test(body)) {
    throw new Error("horizontal master is not safe for the launch composition");
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1366">
  <rect width="1024" height="1366" fill="#006C6A"/>
  <g transform="translate(128 555) scale(0.5)">
${indent(body.trim(), 4)}
  </g>
</svg>
`;
}

async function populateAssetCatalog(root, masters, launchSvg) {
  const catalogRoot = path.join(root, catalogRelativePath);
  const imageSets = [
    ["BodyFlowSymbol", "bodyflow-symbol.svg", masters.get("symbol").contents, "original"],
    ["BodyFlowWordmark", "bodyflow-wordmark.svg", masters.get("wordmark").contents, "original"],
    ["BodyFlowHorizontal", "bodyflow-horizontal.svg", masters.get("horizontal").contents, "original"],
    ["BodyFlowMonochrome", "bodyflow-symbol-monochrome.svg", masters.get("monochrome").contents, "template"],
    ["BodyFlowNegative", "bodyflow-symbol-negative.svg", masters.get("negative").contents, "template"],
    ["BodyFlowLaunch", "bodyflow-launch.svg", launchSvg, "original"],
  ];

  for (const [name, filename, contents, intent] of imageSets) {
    const imageSetRoot = path.join(catalogRoot, `${name}.imageset`);
    await atomicWrite(path.join(imageSetRoot, filename), contents);
    await atomicWrite(
      path.join(imageSetRoot, "Contents.json"),
      `${JSON.stringify(imageSetContents(filename, intent), null, 2)}\n`,
    );
  }

  const appIconRoot = path.join(catalogRoot, "AppIcon.appiconset");
  for (const job of appIconJobs) {
    const filename = path.basename(job.asset.path);
    await atomicWrite(
      path.join(appIconRoot, filename),
      await readFile(path.join(root, job.asset.path)),
    );
  }
  await atomicWrite(
    path.join(appIconRoot, "Contents.json"),
    `${JSON.stringify(appIconContents(), null, 2)}\n`,
  );
  await atomicWrite(
    path.join(catalogRoot, "AccentColor.colorset/Contents.json"),
    `${JSON.stringify(accentColorContents(), null, 2)}\n`,
  );
}

function imageSetContents(filename, intent) {
  return {
    images: [{ filename, idiom: "universal" }],
    info: { author: "xcode", version: 1 },
    properties: {
      "preserves-vector-representation": true,
      "template-rendering-intent": intent,
    },
  };
}

function appIconContents() {
  return {
    images: [
      {
        filename: "bodyflow-app-icon-default-1024.png",
        idiom: "universal",
        platform: "ios",
        size: "1024x1024",
      },
      {
        appearances: [{ appearance: "luminosity", value: "dark" }],
        filename: "bodyflow-app-icon-dark-1024.png",
        idiom: "universal",
        platform: "ios",
        size: "1024x1024",
      },
      {
        appearances: [{ appearance: "luminosity", value: "tinted" }],
        filename: "bodyflow-app-icon-tinted-1024.png",
        idiom: "universal",
        platform: "ios",
        size: "1024x1024",
      },
    ],
    info: { author: "xcode", version: 1 },
  };
}

function accentColorContents() {
  return {
    colors: [
      {
        color: {
          "color-space": "srgb",
          components: {
            alpha: "1.000",
            blue: "0.403922",
            green: "0.427451",
            red: "0.000000",
          },
        },
        idiom: "universal",
      },
      {
        appearances: [{ appearance: "luminosity", value: "dark" }],
        color: {
          "color-space": "srgb",
          components: {
            alpha: "1.000",
            blue: "0.478431",
            green: "0.686275",
            red: "0.831373",
          },
        },
        idiom: "universal",
      },
    ],
    info: { author: "xcode", version: 1 },
  };
}

function vectorJob(id, filename, role, masterId) {
  return {
    masterId,
    asset: {
      id,
      path: `design/brand/exports/${filename}`,
      media_type: "image/svg+xml",
      role,
      alpha: "vector",
      color_space: "sRGB",
    },
  };
}

function squareRasterJobs(role, masterId, sizes) {
  return sizes.map((size) => rasterJob(role, masterId, size, size));
}

function widthRasterJobs(role, masterId, widths, sourceWidth, sourceHeight) {
  return widths.map((width) =>
    rasterJob(
      role,
      masterId,
      width,
      Math.round((width * sourceHeight) / sourceWidth),
    ));
}

function rasterJob(role, masterId, width, height) {
  return {
    masterId,
    asset: {
      id: `${role}-png-${width}`,
      path: `design/brand/exports/bodyflow-${role}-${width}.png`,
      media_type: "image/png",
      role,
      width,
      height,
      alpha: "transparent",
      color_space: "sRGB",
    },
  };
}

function appIconJob(id, filename, variant) {
  return {
    variant,
    asset: {
      id,
      path: `design/brand/exports/${filename}`,
      media_type: "image/png",
      role: "app_icon",
      width: 1024,
      height: 1024,
      alpha: "opaque",
      color_space: "sRGB",
    },
  };
}

function reviewAsset(id, filename) {
  return {
    id,
    path: `design/brand/exports/${filename}`,
    media_type: "image/png",
    role: "review",
    width: 1600,
    height: 1000,
    alpha: "opaque",
    color_space: "sRGB",
  };
}

function sha256(contents) {
  return createHash("sha256").update(contents).digest("hex");
}

function indent(value, spaces) {
  const prefix = " ".repeat(spaces);
  return value.split("\n").map((line) => `${prefix}${line}`).join("\n");
}

async function fileExists(filename) {
  try {
    await access(filename);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const result = await renderBodyFlowBrandAssets(defaultRepositoryRoot);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
