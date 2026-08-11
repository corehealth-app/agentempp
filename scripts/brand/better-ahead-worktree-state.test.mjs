import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, rm, symlink, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

import { betterAheadWorktreeState } from "./better-ahead-worktree-state.mjs";

const runFile = promisify(execFile);

test("parses NUL-delimited porcelain for spaces, non-ASCII, symlinks, deletion, and rename", async (context) => {
  const repository = await createChangedRepository(context);

  const state = await betterAheadWorktreeState(repository);

  assert.equal(state.schemaVersion, 1);
  assert.deepEqual(
    state.paths.map(({ path: relativePath }) => relativePath),
    [
      "deleted.txt",
      "link-to-modified",
      "modified.txt",
      "não rastreado.txt",
      "renamed ü.txt",
      "space name.txt",
    ],
  );
  const deleted = entry(state, "deleted.txt");
  assert.equal(deleted.status, " D");
  assert.equal(deleted.state, "missing");
  assert.equal(deleted.fileType, "missing");
  assert.equal(deleted.byteSize, null);
  assert.equal(deleted.sha256, null);

  const renamed = entry(state, "renamed ü.txt");
  assert.equal(renamed.status, "R ");
  assert.equal(renamed.originalPath, "rename old.txt");
  assert.equal(renamed.fileType, "regular_file");
  assert.match(renamed.sha256, /^[0-9a-f]{64}$/);

  const symbolicLink = entry(state, "link-to-modified");
  assert.equal(symbolicLink.status, "??");
  assert.equal(symbolicLink.fileType, "symbolic_link");
  assert.equal(symbolicLink.state, "present");
  assert.equal(symbolicLink.sha256, null);

  for (const regularFile of state.paths.filter(({ fileType }) => fileType === "regular_file")) {
    assert.equal(regularFile.state, "present", regularFile.path);
    assert.ok(regularFile.byteSize >= 0, regularFile.path);
    assert.match(regularFile.sha256, /^[0-9a-f]{64}$/, regularFile.path);
  }
  assert.equal(JSON.stringify(state).includes(repository), false);
  assert.equal(Object.hasOwn(state, "timestamp"), false);
});

test("exact exclusion removes only one named file", async (context) => {
  const repository = await createChangedRepository(context);

  const state = await betterAheadWorktreeState(repository, {
    excludeExact: ["space name.txt"],
  });

  assert.equal(state.paths.some(({ path: relativePath }) => relativePath === "space name.txt"), false);
  assert.equal(state.paths.some(({ path: relativePath }) => relativePath === "não rastreado.txt"), true);
  assert.equal(state.paths.some(({ path: relativePath }) => relativePath === "modified.txt"), true);
});

test("exact exclusion accepts one clean tracked regular file before its controlled mutation", async (context) => {
  const repository = await createRepository(context);
  await writeFile(path.join(repository, "controlled-evidence.txt"), "before\n");
  await git(repository, ["add", "controlled-evidence.txt"]);
  await git(repository, ["commit", "--quiet", "-m", "track controlled evidence"]);

  const before = await betterAheadWorktreeState(repository, {
    excludeExact: ["controlled-evidence.txt"],
  });
  assert.deepEqual(before.paths, []);

  await writeFile(path.join(repository, "controlled-evidence.txt"), "after\n");
  const after = await betterAheadWorktreeState(repository, {
    excludeExact: ["controlled-evidence.txt"],
  });
  assert.deepEqual(after.paths, []);
});

test("exact exclusion never hides either side of a rename or copy record", async (context) => {
  const repository = await createRepository(context);
  await writeFile(path.join(repository, "original.txt"), "original\n");
  await git(repository, ["add", "original.txt"]);
  await git(repository, ["commit", "--quiet", "-m", "track rename source"]);
  await git(repository, ["mv", "original.txt", "renamed.txt"]);

  await assert.rejects(
    betterAheadWorktreeState(repository, { excludeExact: ["renamed.txt"] }),
    /rename or copy/i,
  );
  await assert.rejects(
    betterAheadWorktreeState(repository, { excludeExact: ["original.txt"] }),
    /rename or copy/i,
  );
});

test("exact exclusion rejects absolute, traversal, wildcard, root, and directory allowances", async (context) => {
  const repository = await createChangedRepository(context);
  await mkdir(path.join(repository, "evidence"), { recursive: true });
  await writeFile(path.join(repository, "evidence", "one.txt"), "one\n");

  for (const invalid of [
    "/absolute.txt",
    "../outside.txt",
    "*.txt",
    ".",
    "evidence",
  ]) {
    await assert.rejects(
      betterAheadWorktreeState(repository, { excludeExact: [invalid] }),
      /exclude-exact/i,
      invalid,
    );
  }
});

test("required prefix accepts only present regular files below one non-root directory", async (context) => {
  const repository = await createRepository(context);
  await mkdir(path.join(repository, "evidence"), { recursive: true });
  await writeFile(path.join(repository, "evidence", "one.txt"), "one\n");
  await writeFile(path.join(repository, "evidence", "dois ü.txt"), "two\n");

  const state = await betterAheadWorktreeState(repository, {
    requireOnlyPrefix: "evidence",
  });

  assert.deepEqual(
    state.paths.map(({ path: relativePath }) => relativePath),
    ["evidence/dois ü.txt", "evidence/one.txt"],
  );
});

test("required prefix rejects root, traversal, sibling paths, symlinks, and an empty state", async (context) => {
  const repository = await createRepository(context);
  await mkdir(path.join(repository, "evidence"), { recursive: true });
  await writeFile(path.join(repository, "evidence", "one.txt"), "one\n");

  await assert.rejects(
    betterAheadWorktreeState(repository, { requireOnlyPrefix: "." }),
    /require-only-prefix/i,
  );
  await assert.rejects(
    betterAheadWorktreeState(repository, { requireOnlyPrefix: "../evidence" }),
    /require-only-prefix/i,
  );

  await writeFile(path.join(repository, "sibling.txt"), "sibling\n");
  await assert.rejects(
    betterAheadWorktreeState(repository, { requireOnlyPrefix: "evidence" }),
    /outside required prefix/i,
  );
  await unlink(path.join(repository, "sibling.txt"));

  await symlink("one.txt", path.join(repository, "evidence", "link"));
  await assert.rejects(
    betterAheadWorktreeState(repository, { requireOnlyPrefix: "evidence" }),
    /regular file/i,
  );
  await unlink(path.join(repository, "evidence", "link"));
  await unlink(path.join(repository, "evidence", "one.txt"));
  await assert.rejects(
    betterAheadWorktreeState(repository, { requireOnlyPrefix: "evidence" }),
    /at least one changed path/i,
  );
});

async function createChangedRepository(context) {
  const repository = await createRepository(context);
  await writeFile(path.join(repository, "modified.txt"), "before\n");
  await writeFile(path.join(repository, "deleted.txt"), "deleted\n");
  await writeFile(path.join(repository, "rename old.txt"), "renamed\n");
  await git(repository, ["add", "."]);
  await git(repository, ["commit", "--quiet", "-m", "fixture baseline"]);

  await writeFile(path.join(repository, "modified.txt"), "after\n");
  await unlink(path.join(repository, "deleted.txt"));
  await git(repository, ["mv", "rename old.txt", "renamed ü.txt"]);
  await writeFile(path.join(repository, "space name.txt"), "space\n");
  await writeFile(path.join(repository, "não rastreado.txt"), "unicode\n");
  await symlink("modified.txt", path.join(repository, "link-to-modified"));
  return repository;
}

async function createRepository(context) {
  const repository = await mkdtemp(path.join(tmpdir(), "better-ahead-state-"));
  context.after(async () => {
    await rm(repository, { recursive: true, force: true });
  });
  await git(repository, ["init", "--quiet"]);
  await git(repository, ["config", "user.name", "Fixture"]);
  await git(repository, ["config", "user.email", "fixture@example.invalid"]);
  await writeFile(path.join(repository, ".gitignore"), "\n");
  await git(repository, ["add", ".gitignore"]);
  await git(repository, ["commit", "--quiet", "-m", "initial"]);
  return repository;
}

async function git(repository, arguments_) {
  return runFile("git", arguments_, { cwd: repository });
}

function entry(state, relativePath) {
  const found = state.paths.find(({ path: candidate }) => candidate === relativePath);
  assert.ok(found, relativePath);
  return found;
}
