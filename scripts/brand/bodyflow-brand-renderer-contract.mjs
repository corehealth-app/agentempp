import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

import sharp from "sharp";

const systemPackageNames = Object.freeze({
  fontconfig: "fontconfig",
  fontconfigConfig: "fontconfig-config",
  fontsLiberation2: "fonts-liberation2",
  libbrotli1: "libbrotli1",
  libexpat1: "libexpat1",
  libfontconfig1: "libfontconfig1",
  libfreetype6: "libfreetype6",
  libpng16: "libpng16-16",
  libxml2: "libxml2",
  libxml2Utils: "libxml2-utils",
});

export const canonicalBrandRenderer = deepFreeze({
  schemaVersion: 1,
  baseImage:
    "node@sha256:d649c27dae7ba0137b3cef5dd75baa422c08dc3d9e3fc0c23dfb172dc3cc6436",
  platform: "linux",
  architecture: "x64",
  node: "22.23.2",
  sharp: {
    aom: "3.13.1",
    archive: "3.8.2",
    cairo: "1.18.4",
    cgif: "0.5.0",
    exif: "0.6.25",
    expat: "2.7.3",
    ffi: "3.5.2",
    fontconfig: "2.17.1",
    freetype: "2.14.1",
    fribidi: "1.0.16",
    glib: "2.86.1",
    harfbuzz: "12.1.0",
    heif: "1.20.2",
    highway: "1.3.0",
    imagequant: "2.4.1",
    lcms: "2.17",
    mozjpeg: "0826579",
    pango: "1.57.0",
    pixman: "0.46.4",
    png: "1.6.50",
    "proxy-libintl": "0.5",
    rsvg: "2.61.2",
    spng: "0.7.4",
    tiff: "4.7.1",
    vips: "8.17.3",
    webp: "1.6.0",
    xml2: "2.15.1",
    "zlib-ng": "2.2.5",
    sharp: "0.34.5",
  },
  sharpConfiguration: {
    concurrency: 1,
    simd: true,
  },
  systemPackages: {
    fontconfig: "2.14.1-4",
    fontconfigConfig: "2.14.1-4",
    fontsLiberation2: "2.1.5-1",
    libbrotli1: "1.0.9-2+b6",
    libexpat1: "2.5.0-1+deb12u2",
    libfontconfig1: "2.14.1-4",
    libfreetype6: "2.12.1+dfsg-5+deb12u4",
    libpng16: "1.6.39-2+deb12u5",
    libxml2: "2.9.14+dfsg-1.3~deb12u6",
    libxml2Utils: "2.9.14+dfsg-1.3~deb12u6",
  },
  fonts: {
    regular: {
      path:
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
      sha256:
        "8d91388f1d3604b3b8ae0e3ee2d140e50cd6122f9214514f4aca772540a4076d",
    },
    bold: {
      path:
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf",
      sha256:
        "ba0e0dc3f7aca5b0afbc31e800531ee43be3aa79ae35b2ef1f6470a9547765c4",
    },
  },
});

export function observeBrandRenderer({ sharpVersions = sharp.versions } = {}) {
  return {
    baseImage: process.env.BODYFLOW_BRAND_BASE_IMAGE,
    platform: process.platform,
    architecture: process.arch,
    node: process.versions.node,
    sharp: { ...sharpVersions },
    sharpConfiguration: {
      concurrency: sharp.concurrency(),
      simd: sharp.simd(),
    },
    systemPackages: Object.fromEntries(
      Object.entries(systemPackageNames).map(([field, packageName]) => [
        field,
        observeSystemPackage(packageName),
      ]),
    ),
    fonts: {
      regular: observeFont("Arial:style=Regular"),
      bold: observeFont("Arial:style=Bold"),
    },
  };
}

export function validateCanonicalBrandRenderer(observed) {
  const { schemaVersion: _schemaVersion, ...expectedRuntime } =
    canonicalBrandRenderer;
  const errors = [];
  compareExact(errors, expectedRuntime, observed);
  return errors;
}

export function assertCanonicalBrandRenderer() {
  const errors = validateCanonicalBrandRenderer(observeBrandRenderer());
  if (errors.length === 0) return;

  throw new Error(
    [
      "BodyFlow brand renderer is not canonical.",
      ...errors.map((error) => "- " + error),
      "Use pnpm --filter @mpp/scripts brand:render to render in the pinned container.",
    ].join("\n"),
  );
}

function observeSystemPackage(packageName) {
  try {
    return execFileSync(
      "dpkg-query",
      ["-W", "-f=$" + "{Version}", packageName],
      { encoding: "utf8" },
    ).trim();
  } catch {
    return undefined;
  }
}

function observeFont(pattern) {
  try {
    const fontPath = execFileSync(
      "fc-match",
      ["-f", "%{file}", pattern],
      { encoding: "utf8" },
    ).trim();
    return {
      path: fontPath,
      sha256: createHash("sha256")
        .update(readFileSync(fontPath))
        .digest("hex"),
    };
  } catch {
    return { path: undefined, sha256: undefined };
  }
}

function compareExact(errors, expected, received, prefix = "") {
  for (const [key, expectedValue] of Object.entries(expected)) {
    const field = prefix ? prefix + "." + key : key;
    const receivedValue = isPlainObject(received) ? received[key] : undefined;
    if (isPlainObject(expectedValue)) {
      compareExact(errors, expectedValue, receivedValue, field);
    } else if (expectedValue !== receivedValue) {
      errors.push(
        field + ": expected " + expectedValue + ", received " + receivedValue,
      );
    }
  }

  if (!isPlainObject(received)) return;
  for (const key of Object.keys(received)) {
    if (Object.hasOwn(expected, key)) continue;
    const field = prefix ? prefix + "." + key : key;
    errors.push(field + ": unexpected field");
  }
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function deepFreeze(value) {
  for (const child of Object.values(value)) {
    if (child !== null && typeof child === "object") {
      deepFreeze(child);
    }
  }
  return Object.freeze(value);
}
