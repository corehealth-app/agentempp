import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import {
  chmod,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import test from "node:test";

import {
  canonicalBrandRenderer,
  observeBrandRenderer,
  validateCanonicalBrandRenderer,
} from "./bodyflow-brand-renderer-contract.mjs";

const execFileAsync = promisify(execFile);
const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(moduleDirectory, "../..");
const manifestPath = path.join(
  repositoryRoot,
  "design/brand/bodyflow-brand-assets.json",
);
const appIconCopyPaths = [
  "bodyflow-app-icon-default-1024.png",
  "bodyflow-app-icon-dark-1024.png",
  "bodyflow-app-icon-tinted-1024.png",
].map((filename) =>
  path.join(
    repositoryRoot,
    "apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets/AppIcon.appiconset",
    filename,
  ),
);
const expectedCanonicalRenderer = {
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
};

test("pins the complete canonical renderer identity", () => {
  assert.deepEqual(canonicalBrandRenderer, expectedCanonicalRenderer);
});

test("accepts only an exact canonical observation", () => {
  const canonicalObservation = {
    baseImage: expectedCanonicalRenderer.baseImage,
    platform: expectedCanonicalRenderer.platform,
    architecture: expectedCanonicalRenderer.architecture,
    node: expectedCanonicalRenderer.node,
    sharp: { ...expectedCanonicalRenderer.sharp },
    sharpConfiguration: { ...expectedCanonicalRenderer.sharpConfiguration },
    systemPackages: { ...expectedCanonicalRenderer.systemPackages },
    fonts: {
      regular: { ...expectedCanonicalRenderer.fonts.regular },
      bold: { ...expectedCanonicalRenderer.fonts.bold },
    },
  };

  assert.deepEqual(validateCanonicalBrandRenderer(canonicalObservation), []);
  assert.deepEqual(
    validateCanonicalBrandRenderer({
      ...canonicalObservation,
      platform: "darwin",
      architecture: "arm64",
    }),
    [
      "platform: expected linux, received darwin",
      "architecture: expected x64, received arm64",
    ],
  );
  assert.deepEqual(
    validateCanonicalBrandRenderer({
      ...canonicalObservation,
      sharp: { ...canonicalObservation.sharp, "zlib-ng": "different" },
    }),
    ["sharp.zlib-ng: expected 2.2.5, received different"],
  );
  assert.deepEqual(
    validateCanonicalBrandRenderer({
      ...canonicalObservation,
      sharpConfiguration: {
        ...canonicalObservation.sharpConfiguration,
        concurrency: 8,
      },
      systemPackages: {
        ...canonicalObservation.systemPackages,
        fontconfig: "different",
      },
    }),
    [
      "sharpConfiguration.concurrency: expected 1, received 8",
      "systemPackages.fontconfig: expected 2.14.1-4, received different",
    ],
  );
  assert.deepEqual(
    validateCanonicalBrandRenderer({
      ...canonicalObservation,
      fonts: {
        ...canonicalObservation.fonts,
        bold: { ...canonicalObservation.fonts.bold, sha256: "different" },
      },
    }),
    [
      "fonts.bold.sha256: expected ba0e0dc3f7aca5b0afbc31e800531ee43be3aa79ae35b2ef1f6470a9547765c4, received different",
    ],
  );
  assert.deepEqual(
    validateCanonicalBrandRenderer({
      ...canonicalObservation,
      unverifiedRuntime: true,
    }),
    ["unverifiedRuntime: unexpected field"],
  );
});

test("observes every Sharp native version entry", () => {
  const observed = observeBrandRenderer({
    sharpVersions: {
      ...expectedCanonicalRenderer.sharp,
      futureNativeLibrary: "1.0.0",
    },
  });

  assert.equal(observed.sharp.futureNativeLibrary, "1.0.0");
  assert.match(
    validateCanonicalBrandRenderer(observed).join("\n"),
    /sharp\.futureNativeLibrary: unexpected field/,
  );
});

test("records the canonical renderer in the brand manifest", async () => {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  assert.deepEqual(manifest.renderer, canonicalBrandRenderer);
});

test("refuses a direct noncanonical render before changing approved outputs", async (context) => {
  if (validateCanonicalBrandRenderer(observeBrandRenderer()).length === 0) {
    context.skip("the test process is already running in the canonical renderer");
    return;
  }

  const manifestBefore = await readFile(manifestPath);
  const manifest = JSON.parse(manifestBefore.toString("utf8"));
  const outputHashesBefore = await hashesForExports(manifest.exports);
  const appIconHashesBefore = await hashesForPaths(appIconCopyPaths);

  await assert.rejects(
    execFileAsync(process.execPath, [
      path.join(moduleDirectory, "render-bodyflow-brand-assets.mjs"),
    ], {
      cwd: repositoryRoot,
      env: { ...process.env },
    }),
    (error) => {
      assert.match(
        `${error.stderr ?? ""}`,
        /BodyFlow brand renderer is not canonical/,
      );
      return true;
    },
  );

  assert.deepEqual(await readFile(manifestPath), manifestBefore);
  assert.deepEqual(await hashesForExports(manifest.exports), outputHashesBefore);
  assert.deepEqual(await hashesForPaths(appIconCopyPaths), appIconHashesBefore);
});

test("runs the immutable image id returned by docker build", async (context) => {
  const fixture = await createRunnerFixture(context);
  const imageId = "sha256:fixture-canonical-image-a";

  await runFixtureRunner(fixture, {
    mode: "--check",
    imageId,
    renderIdentical: true,
  });

  const log = await readFile(fixture.dockerLog, "utf8");
  assert.match(log, new RegExp(`^run-image=${imageId}$`, "m"));
  assert.match(log, /^run-network=none$/m);
  assert.match(log, /^payload-order=assets,review,validate$/m);
});

test("keeps independent image ids isolated across concurrent runners", async (context) => {
  const first = await createRunnerFixture(context);
  const second = await createRunnerFixture(context);

  await Promise.all([
    runFixtureRunner(first, {
      mode: "--check",
      imageId: "sha256:fixture-canonical-image-first",
      renderIdentical: true,
    }),
    runFixtureRunner(second, {
      mode: "--check",
      imageId: "sha256:fixture-canonical-image-second",
      renderIdentical: true,
    }),
  ]);

  assert.match(
    await readFile(first.dockerLog, "utf8"),
    /^run-image=sha256:fixture-canonical-image-first$/m,
  );
  assert.match(
    await readFile(second.dockerLog, "utf8"),
    /^run-image=sha256:fixture-canonical-image-second$/m,
  );
});

test("check mode accepts identical output without promoting", async (context) => {
  const fixture = await createRunnerFixture(context);

  await runFixtureRunner(fixture, {
    mode: "--check",
    renderIdentical: true,
  });

  await assertOriginalRunnerOutputs(fixture);
  await assertNoRunnerTransactions(fixture);
});

test("check mode rejects differences without promoting", async (context) => {
  const fixture = await createRunnerFixture(context);

  await assert.rejects(runFixtureRunner(fixture, { mode: "--check" }));

  await assertOriginalRunnerOutputs(fixture);
  await assertNoRunnerTransactions(fixture);
});

test("keeps repository outputs unchanged when the staged review render fails", async (context) => {
  const fixture = await createRunnerFixture(context);

  await assert.rejects(
    runFixtureRunner(fixture, { mode: "--write", failReview: true }),
  );

  await assertOriginalRunnerOutputs(fixture);
});

test("keeps repository outputs unchanged when staged validation fails", async (context) => {
  const fixture = await createRunnerFixture(context);

  await assert.rejects(
    runFixtureRunner(fixture, { mode: "--write", failValidation: true }),
  );

  await assertOriginalRunnerOutputs(fixture);
});

test("preserves a concurrent edit instead of overwriting its snapshot", async (context) => {
  const fixture = await createRunnerFixture(context);

  await assert.rejects(
    runFixtureRunner(fixture, { mode: "--write", concurrentDesignEdit: true }),
  );

  assert.equal(await readFile(fixture.designSentinel, "utf8"), "concurrent design\n");
  assert.equal(await readFile(fixture.assetsSentinel, "utf8"), "original assets\n");
});

test("rolls back both trees when the second candidate install fails", async (context) => {
  const fixture = await createRunnerFixture(context);

  await assert.rejects(
    runFixtureRunner(fixture, { mode: "--write", failRenameAt: 4 }),
  );

  await assertOriginalRunnerOutputs(fixture);
  await assertNoRunnerTransactions(fixture);
});

test("restores both trees when TERM arrives after a capture rename", async (context) => {
  const fixture = await createRunnerFixture(context);

  await assert.rejects(
    runFixtureRunner(fixture, { mode: "--write", signalAfterRenameAt: 1 }),
  );

  await assertOriginalRunnerOutputs(fixture);
  await assertNoRunnerTransactions(fixture);
});

test("restores both trees when TERM arrives after an install rename", async (context) => {
  const fixture = await createRunnerFixture(context);

  await assert.rejects(
    runFixtureRunner(fixture, { mode: "--write", signalAfterRenameAt: 3 }),
  );

  await assertOriginalRunnerOutputs(fixture);
  await assertNoRunnerTransactions(fixture);
});

test("restores a capture when rename reports failure after moving", async (context) => {
  const fixture = await createRunnerFixture(context);

  await assert.rejects(
    runFixtureRunner(fixture, { mode: "--write", failAfterRenameAt: 1 }),
  );

  await assertOriginalRunnerOutputs(fixture);
  await assertNoRunnerTransactions(fixture);
});

test("restores an install when rename reports failure after moving", async (context) => {
  const fixture = await createRunnerFixture(context);

  await assert.rejects(
    runFixtureRunner(fixture, { mode: "--write", failAfterRenameAt: 3 }),
  );

  await assertOriginalRunnerOutputs(fixture);
  await assertNoRunnerTransactions(fixture);
});

test("preserves an edit made through an open descriptor to the captured tree", async (context) => {
  const fixture = await createRunnerFixture(context);

  await assert.rejects(
    runFixtureRunner(fixture, { mode: "--write", mutateOldAfterRenameAt: 3 }),
  );

  assert.equal(
    await readFile(fixture.designSentinel, "utf8"),
    "concurrent captured design\n",
  );
  assert.equal(await readFile(fixture.assetsSentinel, "utf8"), "original assets\n");
  await assertNoRunnerTransactions(fixture);
});

test("promotes staged outputs after both renderers succeed", async (context) => {
  const fixture = await createRunnerFixture(context);

  await runFixtureRunner(fixture, { mode: "--write" });

  assert.equal(await readFile(fixture.designSentinel, "utf8"), "rendered design\n");
  assert.equal(await readFile(fixture.assetsSentinel, "utf8"), "rendered assets\n");
  await assertNoRunnerTransactions(fixture);
});

test("reports cleanup failure and preserves the recovery transaction", async (context) => {
  const fixture = await createRunnerFixture(context);

  await assert.rejects(
    runFixtureRunner(fixture, { mode: "--write", failTransactionCleanup: true }),
  );

  assert.equal(await readFile(fixture.designSentinel, "utf8"), "rendered design\n");
  assert.equal(await readFile(fixture.assetsSentinel, "utf8"), "rendered assets\n");
  assert.equal((await stat(fixture.lockPath)).isDirectory(), true);
  assert.equal(
    (await readdir(path.join(fixture.root, "design"))).some((name) =>
      name.startsWith(".bodyflow-brand-transaction."),
    ),
    true,
  );
});

test("promotes complete trees and removes obsolete generated files", async (context) => {
  const fixture = await createRunnerFixture(context);
  const obsoleteDesign = path.join(fixture.root, "design/brand/obsolete.txt");
  const obsoleteAssets = path.join(fixture.assetsRoot, "obsolete.txt");
  await writeFile(obsoleteDesign, "obsolete design\n");
  await writeFile(obsoleteAssets, "obsolete assets\n");

  await runFixtureRunner(fixture, { mode: "--write", removeObsolete: true });

  await assert.rejects(readFile(obsoleteDesign), { code: "ENOENT" });
  await assert.rejects(readFile(obsoleteAssets), { code: "ENOENT" });
});

test("uses a Docker-safe temporary root when TMPDIR contains a comma", async (context) => {
  const fixture = await createRunnerFixture(context);
  const unsafeTemporaryRoot = path.join(fixture.root, "tmp,with space");
  await mkdir(unsafeTemporaryRoot);

  await runFixtureRunner(fixture, {
    mode: "--check",
    renderIdentical: true,
    temporaryRoot: unsafeTemporaryRoot,
  });

  await assertOriginalRunnerOutputs(fixture);
});

test("recovers a stale renderer lock owned by a dead pid", async (context) => {
  const fixture = await createRunnerFixture(context);
  await mkdir(fixture.lockPath);
  await writeFile(path.join(fixture.lockPath, "pid"), "99999999\n");

  await runFixtureRunner(fixture, {
    mode: "--check",
    renderIdentical: true,
  });

  await assertOriginalRunnerOutputs(fixture);
  await assertNoRunnerTransactions(fixture);
});

test("recovers a stale renderer lock after pid reuse", async (context) => {
  const fixture = await createRunnerFixture(context);
  await mkdir(fixture.lockPath);
  await writeFile(path.join(fixture.lockPath, "pid"), `${process.pid}\n`);
  await writeFile(
    path.join(fixture.lockPath, "start"),
    "Mon Jan  1 00:00:00 1990\n",
  );

  await runFixtureRunner(fixture, {
    mode: "--check",
    renderIdentical: true,
  });

  await assertOriginalRunnerOutputs(fixture);
  await assertNoRunnerTransactions(fixture);
});

test("preserves a stale lock when crash-recovery transactions exist", async (context) => {
  const fixture = await createRunnerFixture(context);
  const recoveryDirectory = path.join(
    fixture.root,
    "design/.bodyflow-brand-transaction.crashed",
  );
  await mkdir(fixture.lockPath);
  await writeFile(path.join(fixture.lockPath, "pid"), "99999999\n");
  await mkdir(recoveryDirectory);
  await writeFile(path.join(recoveryDirectory, "preserved.txt"), "recovery data\n");

  await assert.rejects(
    runFixtureRunner(fixture, { mode: "--check", renderIdentical: true }),
  );

  assert.equal(
    await readFile(path.join(recoveryDirectory, "preserved.txt"), "utf8"),
    "recovery data\n",
  );
  assert.equal(await readFile(path.join(fixture.lockPath, "pid"), "utf8"), "99999999\n");
});

test("locks the canonical container dependencies", async () => {
  const dockerfile = await readFile(
    path.join(moduleDirectory, "canonical-renderer/Dockerfile"),
    "utf8",
  );
  const packageLock = JSON.parse(
    await readFile(
      path.join(moduleDirectory, "canonical-renderer/package-lock.json"),
      "utf8",
    ),
  );

  assert.deepEqual(
    dockerfile.split("\n").filter((line) => line.startsWith("FROM ")),
    [
      "FROM node@sha256:d649c27dae7ba0137b3cef5dd75baa422c08dc3d9e3fc0c23dfb172dc3cc6436",
    ],
  );
  for (const [packageName, version] of [
    ["fontconfig", "2.14.1-4"],
    ["fontconfig-config", "2.14.1-4"],
    ["fonts-liberation2", "2.1.5-1"],
    ["libbrotli1", "1.0.9-2+b6"],
    ["libexpat1", "2.5.0-1+deb12u2"],
    ["libfontconfig1", "2.14.1-4"],
    ["libfreetype6", "2.12.1+dfsg-5+deb12u4"],
    ["libpng16-16", "1.6.39-2+deb12u5"],
    ["libxml2", "2.9.14+dfsg-1.3~deb12u6"],
    ["libxml2-utils", "2.9.14+dfsg-1.3~deb12u6"],
  ]) {
    assert.ok(
      dockerfile.includes(packageName + "=" + version),
      packageName + " must be installed at its exact version",
    );
  }
  assert.equal(packageLock.packages["node_modules/sharp"].version, "0.34.5");
  assert.equal(
    packageLock.packages["node_modules/@img/sharp-linux-x64"].version,
    "0.34.5",
  );
  assert.equal(
    packageLock.packages["node_modules/@img/sharp-libvips-linux-x64"].version,
    "1.2.4",
  );
});

async function hashesForExports(exports) {
  const result = {};
  for (const asset of exports) {
    const absolutePath = path.join(repositoryRoot, asset.path);
    const metadata = await stat(absolutePath);
    assert.equal(metadata.isFile(), true);
    result[asset.id] = createHash("sha256")
      .update(await readFile(absolutePath))
      .digest("hex");
  }
  return result;
}

async function hashesForPaths(paths) {
  const result = {};
  for (const filePath of paths) {
    result[filePath] = createHash("sha256")
      .update(await readFile(filePath))
      .digest("hex");
  }
  return result;
}

async function assertOriginalRunnerOutputs(fixture) {
  assert.equal(await readFile(fixture.designSentinel, "utf8"), "original design\n");
  assert.equal(await readFile(fixture.assetsSentinel, "utf8"), "original assets\n");
}

async function assertNoRunnerTransactions(fixture) {
  const designSiblings = await readdir(path.join(fixture.root, "design"));
  const assetSiblings = await readdir(path.dirname(fixture.assetsRoot));
  assert.deepEqual(
    designSiblings.filter((name) => name.startsWith(".bodyflow-brand-transaction.")),
    [],
  );
  assert.deepEqual(
    assetSiblings.filter((name) => name.startsWith(".bodyflow-assets-transaction.")),
    [],
  );
  await assert.rejects(stat(fixture.lockPath), { code: "ENOENT" });
}

async function rendererLockPath(root) {
  const { stdout } = await execFileAsync(
    "sh",
    ["-c", 'printf %s "$1" | cksum', "sh", root],
  );
  const repositoryKey = stdout.trim().split(/\s+/)[0];
  return `/tmp/bodyflow-brand-renderer.${repositoryKey}.lock`;
}

async function createRunnerFixture(context) {
  const root = await mkdtemp(path.join(tmpdir(), "bodyflow-brand-runner-"));
  const lockPath = await rendererLockPath(root);
  context.after(async () => {
    await rm(root, { recursive: true, force: true });
    await rm(lockPath, { recursive: true, force: true });
  });

  const fixtureModuleDirectory = path.join(root, "scripts/brand");
  const fixtureContainerDirectory = path.join(
    fixtureModuleDirectory,
    "canonical-renderer",
  );
  const assetsRoot = path.join(
    root,
    "apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets",
  );
  await mkdir(fixtureContainerDirectory, { recursive: true });
  await mkdir(path.join(root, "design/brand"), { recursive: true });
  await mkdir(assetsRoot, { recursive: true });

  const runnerPath = path.join(
    fixtureModuleDirectory,
    "run-bodyflow-brand-renderer.sh",
  );
  await copyFile(
    path.join(moduleDirectory, "run-bodyflow-brand-renderer.sh"),
    runnerPath,
  );

  const designSentinel = path.join(root, "design/brand/generated.txt");
  const assetsSentinel = path.join(assetsRoot, "generated.txt");
  await writeFile(designSentinel, "original design\n");
  await writeFile(assetsSentinel, "original assets\n");

  const fakeBin = path.join(root, "fake-bin");
  const dockerLog = path.join(root, "docker.log");
  const renameCounter = path.join(root, "rename-counter");
  await mkdir(fakeBin, { recursive: true });
  const fakeDockerPath = path.join(fakeBin, "docker");
  await writeFile(fakeDockerPath, fakeDockerSource() + "\n");
  await chmod(fakeDockerPath, 0o755);
  const fakeNodePath = path.join(fakeBin, "node");
  await writeFile(fakeNodePath, fakeNodeSource() + "\n");
  await chmod(fakeNodePath, 0o755);
  const fakeRmPath = path.join(fakeBin, "rm");
  await writeFile(fakeRmPath, fakeRmSource() + "\n");
  await chmod(fakeRmPath, 0o755);
  const fakePsPath = path.join(fakeBin, "ps");
  await writeFile(fakePsPath, fakePsSource() + "\n");
  await chmod(fakePsPath, 0o755);

  return {
    root,
    runnerPath,
    fakeBin,
    dockerLog,
    renameCounter,
    designSentinel,
    assetsSentinel,
    assetsRoot,
    lockPath,
  };
}

async function runFixtureRunner(
  fixture,
  {
    mode,
    imageId = "sha256:fixture-canonical-image",
    renderIdentical = false,
    failReview = false,
    failValidation = false,
    concurrentDesignEdit = false,
    failRenameAt = 0,
    failAfterRenameAt = 0,
    mutateOldAfterRenameAt = 0,
    signalAfterRenameAt = 0,
    failTransactionCleanup = false,
    removeObsolete = false,
    temporaryRoot,
  },
) {
  const environment = {
    ...process.env,
    PATH: [fixture.fakeBin, process.env.PATH].join(path.delimiter),
    REAL_NODE: process.execPath,
    REAL_RM: "/bin/rm",
    FAKE_NODE_RENAME_COUNTER: fixture.renameCounter,
    FAKE_NODE_FAIL_RENAME_AT: String(failRenameAt),
    FAKE_NODE_FAIL_AFTER_RENAME_AT: String(failAfterRenameAt),
    FAKE_NODE_MUTATE_OLD_AFTER_RENAME_AT: String(mutateOldAfterRenameAt),
    FAKE_NODE_SIGNAL_AFTER_RENAME_AT: String(signalAfterRenameAt),
    FAKE_RM_FAIL_TRANSACTION: failTransactionCleanup ? "1" : "0",
    FAKE_DOCKER_LOG: fixture.dockerLog,
    FAKE_DOCKER_IMAGE_ID: imageId,
    FAKE_DOCKER_RENDER_IDENTICAL: renderIdentical ? "1" : "0",
    FAKE_DOCKER_FAIL_REVIEW: failReview ? "1" : "0",
    FAKE_DOCKER_FAIL_VALIDATION: failValidation ? "1" : "0",
    FAKE_DOCKER_CONCURRENT_DESIGN_EDIT: concurrentDesignEdit ? "1" : "0",
    FAKE_DOCKER_REMOVE_OBSOLETE: removeObsolete ? "1" : "0",
    FAKE_DOCKER_LIVE_ROOT: fixture.root,
  };
  if (temporaryRoot !== undefined) environment.TMPDIR = temporaryRoot;

  return execFileAsync("sh", [fixture.runnerPath, mode], {
    cwd: fixture.root,
    env: environment,
  });
}

function fakeDockerSource() {
  return [
    "#!/bin/sh",
    "set -eu",
    'command_name="$1"',
    "shift",
    'if [ "$command_name" = "build" ]; then',
    "  iidfile=",
    '  while [ "$#" -gt 0 ]; do',
    '    if [ "$1" = "--iidfile" ]; then',
    "      shift",
    '      iidfile="$1"',
    "    fi",
    "    shift",
    "  done",
    '  test -n "$iidfile"',
    '  printf "%s\\n" "$FAKE_DOCKER_IMAGE_ID" > "$iidfile"',
    '  printf "build-image=%s\\n" "$FAKE_DOCKER_IMAGE_ID" >> "$FAKE_DOCKER_LOG"',
    "  exit 0",
    "fi",
    'if [ "$command_name" != "run" ]; then',
    "  exit 64",
    "fi",
    "network=",
    "mount_value=",
    "run_image=",
    'while [ "$#" -gt 0 ]; do',
    '  case "$1" in',
    "    --rm)",
    "      shift",
    "      ;;",
    "    --network | --platform | --user | --mount | --tmpfs | --workdir)",
    '      option="$1"',
    "      shift",
    '      test "$#" -gt 0',
    '      value="$1"',
    "      shift",
    '      if [ "$option" = "--network" ]; then network="$value"; fi',
    '      if [ "$option" = "--mount" ]; then mount_value="$value"; fi',
    "      ;;",
    "    -*)",
    "      exit 65",
    "      ;;",
    "    *)",
    '      run_image="$1"',
    "      shift",
    "      break",
    "      ;;",
    "  esac",
    "done",
    'test "$run_image" = "$FAKE_DOCKER_IMAGE_ID"',
    'test "$network" = "none"',
    'case "$mount_value" in',
    "  type=bind,src=*,dst=/workspace) ;;",
    "  *) exit 66 ;;",
    "esac",
    'target_root=$' + '{mount_value#type=bind,src=}',
    'target_root=$' + '{target_root%,dst=/workspace}',
    'case "$target_root" in *,*) exit 67 ;; esac',
    'test -n "$target_root"',
    "payload=",
    'for argument in "$@"; do payload="$argument"; done',
    'case "$payload" in',
    "  *\"node scripts/brand/render-bodyflow-brand-assets.mjs\"*\"node scripts/brand/render-bodyflow-brand-review.mjs\"*\"node scripts/brand/bodyflow-brand-contract.mjs --check\"*) ;;",
    "  *) exit 68 ;;",
    "esac",
    'printf "run-image=%s\\n" "$run_image" >> "$FAKE_DOCKER_LOG"',
    'printf "run-network=%s\\n" "$network" >> "$FAKE_DOCKER_LOG"',
    'printf "payload-order=assets,review,validate\\n" >> "$FAKE_DOCKER_LOG"',
    'if [ "$FAKE_DOCKER_RENDER_IDENTICAL" != "1" ]; then',
    '  printf "rendered design\\n" > "$target_root/design/brand/generated.txt"',
    '  if [ "$FAKE_DOCKER_REMOVE_OBSOLETE" = "1" ]; then',
    '    rm -f "$target_root/design/brand/obsolete.txt"',
    "  fi",
    "fi",
    'if [ "$FAKE_DOCKER_FAIL_REVIEW" = "1" ]; then',
    "  exit 23",
    "fi",
    'if [ "$FAKE_DOCKER_RENDER_IDENTICAL" != "1" ]; then',
    '  printf "rendered assets\\n" > "$target_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets/generated.txt"',
    '  if [ "$FAKE_DOCKER_REMOVE_OBSOLETE" = "1" ]; then',
    '    rm -f "$target_root/apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets/obsolete.txt"',
    "  fi",
    "fi",
    'if [ "$FAKE_DOCKER_FAIL_VALIDATION" = "1" ]; then',
    "  exit 24",
    "fi",
    'if [ "$FAKE_DOCKER_CONCURRENT_DESIGN_EDIT" = "1" ]; then',
    '  printf "concurrent design\\n" > "$FAKE_DOCKER_LIVE_ROOT/design/brand/generated.txt"',
    "fi",
  ].join("\n");
}

function fakeNodeSource() {
  return [
    "#!/bin/sh",
    "set -eu",
    "rename_count=0",
    'if [ "$#" -ge 2 ] && [ "$1" = "-e" ]; then',
    '  case "$2" in',
    "    *renameSync*)",
    "      count=0",
    '      if [ -f "$FAKE_NODE_RENAME_COUNTER" ]; then',
    '        count=$(cat "$FAKE_NODE_RENAME_COUNTER")',
    "      fi",
    "      count=$((count + 1))",
    '      printf "%s\\n" "$count" > "$FAKE_NODE_RENAME_COUNTER"',
    '      if [ "$count" -eq "$FAKE_NODE_FAIL_RENAME_AT" ]; then',
    "        exit 75",
    "      fi",
    '      rename_count="$count"',
    "      ;;",
    "  esac",
    "fi",
    '"$REAL_NODE" "$@"',
    "node_status=$?",
    'if [ "$rename_count" -gt 0 ] && [ "$rename_count" -eq "$FAKE_NODE_MUTATE_OLD_AFTER_RENAME_AT" ]; then',
    '  old_root=$' + '{3%/new}/old',
    '  printf "concurrent captured design\\n" > "$old_root/generated.txt"',
    "fi",
    'if [ "$rename_count" -gt 0 ] && [ "$rename_count" -eq "$FAKE_NODE_FAIL_AFTER_RENAME_AT" ]; then',
    "  exit 75",
    "fi",
    'if [ "$rename_count" -gt 0 ] && [ "$rename_count" -eq "$FAKE_NODE_SIGNAL_AFTER_RENAME_AT" ]; then',
    '  kill -TERM "$PPID"',
    "fi",
    'exit "$node_status"',
  ].join("\n");
}

function fakeRmSource() {
  return [
    "#!/bin/sh",
    "set -eu",
    'if [ "$FAKE_RM_FAIL_TRANSACTION" = "1" ]; then',
    '  for argument in "$@"; do',
    '    case "$argument" in',
    "      */.bodyflow-brand-transaction.*) exit 76 ;;",
    "    esac",
    "  done",
    "fi",
    'exec "$REAL_RM" "$@"',
  ].join("\n");
}

function fakePsSource() {
  return [
    "#!/bin/sh",
    "set -eu",
    'test "$1" = "-p"',
    'process_id="$2"',
    'test "$3" = "-o"',
    'test "$4" = "lstart="',
    'kill -0 "$process_id" 2>/dev/null',
    'printf "fixture-start-%s\\n" "$process_id"',
  ].join("\n");
}
